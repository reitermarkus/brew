require "download"

class ParallelDownloader
  attr_reader :downloads, :download_queue, :size
  private :downloads, :download_queue

  def initialize(*downloads, size: 8)
    @downloads = downloads
    @download_queue = Queue.new
    @size = size

    downloads.each do |dl|
      @download_queue.enq dl
      dl.add_observer self
    end

    @output_mutex = Mutex.new
    @outputters = Queue.new
  end

  def self.width
    @width ||= `/bin/stty size 2>/dev/null`.split[1].to_i
  end

  def self.update_display(message, progress)
    progress_str = " %0.1f %%" % progress

    len = width - progress_str.to_s.length

    str = message.to_s[0, len].to_s.ljust(len)

    split_at = (len / 100.0 * progress).to_i

    "\e[7m" << str[0, split_at].to_s << "\e[0m" << str[split_at..-1] << progress_str << "\n"
  end

  def update
    thread = Thread.new do
      @output_mutex.synchronize do
        until @outputters.empty?
          t = @outputters.deq
          t.kill unless t == Thread.current
        end

        lines = downloads.map { |dl| self.class.update_display(dl.uri, dl.progress) }.join

        if $stdout.tty?
          print "\e[" << downloads.count.to_s << "A" << lines
        else
          print lines if downloads.all?(&:ended?)
        end
      end
    end

    @outputters.enq thread
  end

  def download
    downloading = Queue.new

    if $stdout.tty?
      # Hide cursor to avoid “flickering”.
      print "\e[?25l"
      print "\n" * downloads.count
    end

    until download_queue.empty? && downloading.empty?
      unless download_queue.empty?
        if downloading.size < size
          dl = download_queue.deq
          downloading.enq dl
          dl.start
        end
      end

      unless downloading.empty?
        dl = downloading.deq

        if dl.ended?
          dl.delete_observers
        else
          downloading.enq dl
        end
      end
    end

    until @outputters.empty?
      thread = @outputters.deq
      thread.join
    end
  ensure
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
      Download::Curl.new("https://www.kernel.org/pub/software/scm/git/git-2.14.1.tar.xz", to: destination_dir),
      Download::Curl.new("https://www.python.org/ftp/python/3.6.2/Python-3.6.2.tar.xz", to: destination_dir),
      Download::Curl.new("https://homebrew.bintray.com/bottles/gcc-7.2.0.sierra.bottle.tar.gz", to: destination_dir),
    ]


    puts "==> Starting Downloads …"
    ParallelDownloader.new(*downloads).download

    downloads.each do |dl|
      raise dl.exception if dl.exception
    end
  end
end
