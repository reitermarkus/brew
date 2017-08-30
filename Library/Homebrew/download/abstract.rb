require "uri"
require "pathname"
require "thread"
require "observer"

module Download
  class Abstract
    class Error < StandardError; end

    include Observable

    attr_reader :uri, :destination, :exception

    def initialize(uri, to: Dir.pwd)
      @uri = URI(uri)
      @destination = Pathname(to).expand_path
      @mutex = Mutex.new
      @status = :stopped
      @progress = 0.0
    end

    def uri=(uri)
      @mutex.synchronize do
        @uri = uri
      end

      notify_observers
    end

    def start
      @mutex.synchronize do
        next unless changed(@status != :running)
        @status = :running

        @thread = Thread.new do
          self.status = begin
            self.progress = 0.0
            thread_routine
            self.progress = 100.0
            :finished
          rescue StandardError => e
            @exception = e
            :failed
          end
        end
        @thread.abort_on_exception = true
      end

      notify_observers
    end

    def thread_routine
      raise NotImplementedError
    end

    def stop
      @thread && @thread.terminate
      @thread = nil

      @mutex.synchronize do
        @status = :stopped
      end

      notify_observers
    end

    def wait
      @thread && @thread.join
      @thread = nil
    end

    def status
      @mutex.synchronize do
        @status
      end
    end

    def status=(status)
      @mutex.synchronize do
        next unless changed(@status != status)
        @status = status
      end

      notify_observers
    end
    private :status=

    def progress
      @mutex.synchronize do
        @progress
      end
    end

    def progress=(progress)
      @mutex.synchronize do
        next unless changed(@progress != progress)
        @progress = progress
      end

      notify_observers
    end
    private :progress=

    def ended?
      [:finished, :failed].include?(status)
    end

    # Helpers

    def parse_percentage(string, regex = /(\d+(?:\.\d+)?)\%/)
      Float((string.scan(regex).last || [])[0].to_s)
    end
  end
end
