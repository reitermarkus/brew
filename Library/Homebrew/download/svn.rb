require "download/abstract"

require "open3"

module Download
  class Svn < Abstract
    def initialize(*args, svn_executable: "svn", **options)
      super(*args, **options)
      @svn_executable = svn_executable
    end

    private

    attr_reader :svn_executable

    def thread_routine
      destination.dirname.mkpath

      args = if destination.directory?
        ["up", destination.to_path]
      else
        file_count = 0

        file_counter = Thread.new do
          Open3.popen3(svn_executable, "list", "-R", uri.to_s) do |stdin, stdout, stderr, thread|
            stdin.close
            stderr.close

            stdout.each_line do
              file_count += 1
            end

            thread.join
          end
        end

        ["checkout", uri.to_s, destination.to_path]
      end

      Open3.popen3(svn_executable, *args) do |stdin, stdout, stderr, thread|
        stdin.close

        if file_count
          line_count = -2 # The last two lines are not file names.

          stdout.each_line do
            line_count += 1
            next if line_count > file_count || file_count.zero?
            progress = [line_count.to_f / file_count.to_f * 100, 99.9].min
            self.progress = progress unless progress < self.progress
          end
        else
          stdout.close
        end


        file_counter.join if file_counter
        exit_status = thread.value

        raise Error, stderr.read.strip unless exit_status.success?
        self.progress = 100.0
      end
    end
  end
end
