require "download"

class ParallelDownloader
  attr_reader :downloads, :download_queue, :size
  private :downloads, :download_queue

  def initialize(*downloads, size: 4)
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
    progress = "%0.1f %%" % progress
    len = width - progress.to_s.length - 2
    message.to_s[0, len].to_s.ljust(len) + "  #{progress}\n"
  end

  def update
    thread = Thread.new do
      lines = downloads.map { |dl| self.class.update_display(dl.uri, dl.progress) }.join

      @output_mutex.synchronize do
        if $stdout.tty?
          print ("\e[A" * downloads.count) + lines
        else
          print lines if downloads.all?(&:ended?)
        end
      end
    end

    @outputters.enq thread
  end

  def download
    downloading = Queue.new

    print "\n" * downloads.count if $stdout.tty?

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
  end
end

module Homebrew
  module_function

  def download
    downloads = 3.times.flat_map { |i|
      [
        Download::Curl.new("http://ipv4.download.thinkbroadband.com/1GB.zip?#{i}", to: "/tmp/test/curl#{i}"),
        Download::Git.new("git://github.com/Homebrew/brew.git", to: "/tmp/test/git#{i}"),
        Download::Svn.new("https://caml.inria.fr/svn/ocaml/trunk",  to: "/tmp/test/svn#{i}")
      ]
    }.shuffle


    puts "==> Starting Downloads …"
    ParallelDownloader.new(*downloads).download

    downloads.each do |dl|
      raise dl.exception if dl.exception
    end
  end
end
