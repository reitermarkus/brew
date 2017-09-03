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
      @status = :pending
      @progress = 0.0
    end

    def start
      return if running?

      @mutex.synchronize do
        changed(true)
        @status = :running
        @progress = 0.0

        @thread = Thread.new do
          begin
            thread_routine
            @mutex.synchronize do
              @status = :finished
              @progress = 100.0
            end
            changed(true)
            notify_observers
          rescue StandardError
            self.status = :failed
            raise
          end
        end

        @thread.abort_on_exception = true
      end

      notify_observers
    end

    def start!
      start
      value
    end

    def thread_routine
      raise NotImplementedError
    end

    def stop
      @thread && @thread.terminate
      @thread = nil

      self.status = :pending
    end

    def value
      @thread && @thread.value
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

    def running?
      status == :running
    end

    def pending?
      status == :pending
    end

    def ended?
      [:finished, :failed].include?(status)
    end

    # Helpers

    def parse_percentage(string, regex = /(\d+(?:\.\d+)?)\%/)
      Float((string.scan(regex).last || [])[0].to_s)
    end
  end
end
