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
        ["checkout", uri.to_s, destination.to_path]
      end

      Open3.popen3(svn_executable, *args) do |stdin, stdout, stderr, thread|
        stdin.close
        stdout.close

        exit_status = thread.value

        raise Error, stderr.read.strip unless exit_status.success?
        self.progress = 100.0
      end
    end
  end
end
