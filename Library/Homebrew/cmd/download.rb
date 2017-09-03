require "download"

Homebrew.install_gem_setup_path! "concurrent-ruby", nil, nil
require 'concurrent'

class ParallelDownloader
  attr_reader :downloads, :download_queue, :size, :host_semaphores
  private :downloads, :download_queue, :host_semaphores

  def initialize(*downloads, size: 8, downloads_per_host: {})
    @downloads = downloads
    @download_queue = Queue.new
    @size = size

    hosts = downloads.map(&:uri).map(&:host).uniq

    @host_semaphores = Hash[hosts.map { |h|
      [h, Concurrent::Semaphore.new(downloads_per_host.fetch(h, 1))]
    }]

    downloads.each do |dl|
      @download_queue.enq dl
      dl.add_observer self
    end

    @outputter_thread = Concurrent::SingleThreadExecutor.new
    @outputter_pool = Concurrent::SerializedExecutionDelegator.new(@outputter_thread)
  end

  def self.width
    @width ||= `/bin/stty size 2>/dev/null`.split[1].to_i
  end

  def self.update_display(message, progress)
    progress_str = format(" %0.1f %%", progress)

    len = width - progress_str.to_s.length

    str = message.to_s[0, len].to_s.ljust(len)

    split_at = (len / 100.0 * progress).to_i

    "\e[7m" << str[0, split_at].to_s << "\e[0m" << str[split_at..-1] << progress_str << "\n"
  end

  def update
    @outputter_pool.post do
      lines = downloads.map { |dl| self.class.update_display(dl.uri, dl.progress) }.join

      if $stdout.tty?
        print "\e[" << downloads.count.to_s << "A" << lines
      elsif downloads.all?(&:ended?)
        print lines
      end
    end
  end

  def download
    pool = Concurrent::FixedThreadPool.new(size)
    promises = []

    if $stdout.tty?
      # Hide cursor to avoid “flickering”.
      print "\e[?25l"
      print "\n" * downloads.count
    end

    loop do
      break if download_queue.empty?
      dl = download_queue.deq
      host = dl.uri.host
      if host_semaphores[host].try_acquire
        promises << Concurrent::Promise.execute(executor: pool) do
          begin
            dl.start!
            dl.delete_observer self
          ensure
            host_semaphores[host].release
          end
        end
      else
        download_queue.enq dl
      end
    end

    Concurrent::Promise.zip(*promises).value!

    pool.shutdown
    pool.wait_for_termination
  ensure
    @outputter_pool.shutdown
    @outputter_pool.wait_for_termination

    if $stdout.tty?
      # Don't hide the cursor forever.
      print "\e[?25h"
      $stdout.flush
    end
  end
end

module Homebrew
  module_function

  def download
    destination_dir = Pathname("/tmp/brew-parallel-download")

    destination_dir.mkpath

    downloads = [
      Download::Git.new("git://github.com/Homebrew/brew.git", to: "#{destination_dir}/brew"),
      Download::Svn.new("https://caml.inria.fr/svn/ocaml/trunk",  to: "#{destination_dir}/ocaml"),
      Download::Svn.new("http://abcl.org/svn/trunk/abcl",  to: "#{destination_dir}/abcl"),
      Download::Svn.new("https://ssl.icu-project.org/repos/icu/trunk/icu4c",  to: "#{destination_dir}/icu4c"),
      Download::Curl.new("https://www.kernel.org/pub/software/scm/git/git-2.14.1.tar.xz", to: destination_dir),
      Download::Curl.new("https://www.python.org/ftp/python/3.6.2/Python-3.6.2.tar.xz", to: destination_dir),
      Download::Curl.new("https://homebrew.bintray.com/bottles/gcc-7.2.0.sierra.bottle.tar.gz", to: destination_dir.join("1")),
      Download::Curl.new("https://homebrew.bintray.com/bottles/gcc-7.2.0.sierra.bottle.tar.gz", to: destination_dir.join("2")),
      Download::Curl.new("https://homebrew.bintray.com/bottles/gcc-7.2.0.sierra.bottle.tar.gz", to: destination_dir.join("3")),
      Download::Curl.new("https://homebrew.bintray.com/bottles/gcc-7.2.0.sierra.bottle.tar.gz", to: destination_dir.join("4")),
      Download::Curl.new("https://homebrew.bintray.com/bottles/gcc-7.2.0.sierra.bottle.tar.gz", to: destination_dir.join("5")),
      Download::Curl.new("https://homebrew.bintray.com/bottles/gcc-7.2.0.sierra.bottle.tar.gz", to: destination_dir.join("6")),
      Download::Curl.new("https://homebrew.bintray.com/bottles/gcc-7.2.0.sierra.bottle.tar.gz", to: destination_dir.join("7")),
      Download::Curl.new("https://homebrew.bintray.com/bottles/gcc-7.2.0.sierra.bottle.tar.gz", to: destination_dir.join("8")),
      Download::Curl.new("https://homebrew.bintray.com/bottles/gcc-7.2.0.sierra.bottle.tar.gz", to: destination_dir.join("9")),
    ]

    ParallelDownloader.new(*downloads, downloads_per_host: { "homebrew.bintray.com" => 3 }).download

    downloads.each do |dl|
      raise dl.exception if dl.exception
    end
  end
end
