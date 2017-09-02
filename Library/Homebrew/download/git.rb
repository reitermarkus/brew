require "download/abstract"

require "open3"

module Download
  class Git < Abstract
    def initialize(*args, git_executable: "git", **options)
      super(*args, **options)
      @git_executable = git_executable
    end

    private

    attr_reader :git_executable

    def thread_routine
      destination.dirname.mkpath

      if repo_valid?
        git "--git-dir", git_dir.to_path, "fetch", "--all"
      else
        FileUtils.rm_rf destination.to_path
        git "clone", "--progress", uri.to_s, destination.to_path
      end
    end

    def git_dir
      destination.join(".git")
    end

    def repo_valid?
      *, status = Open3.capture3(git_executable, "--git-dir", git_dir.to_path, "status", "-s")
      status.success?
    end

    def git(*args)
      Open3.popen3(git_executable, *args) do |stdin, stdout, stderr, thread|
        stdin.close
        stdout.close

        buffer = ""
        err = ""

        stderr.each_char do |char|
          buffer << char.sub(",", ".")
          err << char
          next unless char == "%"

          begin
            # 0% -- 33.3%
            self.progress = parse_percentage(buffer, /compressing objects:\s+(\d+)\%/i) / 3.0
          rescue ArgumentError
            begin
              # 33.3% - 66.6%
              self.progress = (100.0 / 3) + parse_percentage(buffer, /receiving objects:\s+(\d+)\%/i) / 3.0
            rescue ArgumentError
              begin
                # 66.6% - 100%
                self.progress = (100.0 / 3 * 2) + parse_percentage(buffer, /resolving deltas:\s+(\d+)\%/i) / 3.0
              rescue ArgumentError
                next
              end
            end
          end

          buffer = ""
        end

        exit_status = thread.value

        raise Error, err.strip unless exit_status.success?
      end
    end
  end
end
