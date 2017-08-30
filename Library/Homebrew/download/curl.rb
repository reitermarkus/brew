require "download/abstract"

require "open3"
require "json"
require "tmpdir"

module Download
  class Curl < Abstract
    FORMAT_VARIABLES = [
      'content_type',
      'filename_effective',
      'ftp_entry_path',
      'http_code',
      'http_connect',
      'http_version',
      'local_ip',
      'local_port',
      'num_connects',
      'num_redirects',
      'proxy_ssl_verify_result',
      'redirect_url',
      'remote_ip',
      'remote_port',
      'scheme',
      'size_download',
      'size_header',
      'size_request',
      'size_upload',
      'speed_download',
      'speed_upload',
      'ssl_verify_result',
      'time_appconnect',
      'time_connect',
      'time_namelookup',
      'time_pretransfer',
      'time_redirect',
      'time_starttransfer',
      'time_total',
      'url_effective',
    ]

    FORMAT_JSON = Hash[FORMAT_VARIABLES.map { |var| [var, "%{#{var}}"] }].to_json

    class CurlError < Error
      attr_reader :code, :variables

      def initialize(code, message, variables: variables)
        @code = code
        @variables = variables
        super(message)
      end
    end

    class InsecureRedirectError < Error; end

    def initialize(*args, curl_executable: "curl", ignore_insecure_redirects: false, **options)
      super(*args, **options)
      @curl_executable = curl_executable
      @ignore_insecure_redirects = ignore_insecure_redirects
    end

    private

    attr_reader :curl_executable, :ignore_insecure_redirects

    def follow_redirect
      output, status = Dir.mktmpdir do |dir|
        r, w = IO.pipe

        pid = fork do
          r.close

          # `chdir` is not thread-safe, so we need to fork.
          Dir.chdir dir do
            output, status = Open3.capture2(
              curl_executable, "--silent", "--head", "--remote-header-name", "--write-out", FORMAT_JSON, "-O", uri.to_s
            )

            w.write output if status.success?
            exit!(status.exitstatus)
          end
        end

        w.close

        Process.wait(pid)

        [r.read, $CHILD_STATUS]
      end

      variables = JSON.parse(output)

      redirect_url = variables["redirect_url"]
      filename = variables["filename_effective"]

      return unless status.success?

      @destination = destination.join(filename) if destination.directory?

      return if redirect_url.empty?

      unless ignore_insecure_redirects
        if uri.to_s.start_with?("https://") && !redirect_url.start_with?("https://")
          raise InsecureRedirectError, "#{uri} -> #{redirect_url}"
        end
      end

      self.uri = URI(redirect_url)
    end

    def thread_routine
      follow_redirect

      path_arguments = ["-o", destination.to_path]

      begin
        args = [
          "--progress-bar",
          "--fail",
          "--show-error",
          "--location",
          "--remote-header-name",
          "--write-out", FORMAT_JSON,
        ]

        destination.dirname.mkpath

        if had_incomplete_download ||= destination.file?
          args << "--continue-at" << "-"
        end

        Open3.popen3(curl_executable, *args, *path_arguments, uri.to_s) do |stdin, stdout, stderr, thread|
          buffer = ""

          stderr.each_char do |char|
            buffer << char.tr(",", ".")
            next unless char == '%'

            begin
              self.progress = parse_percentage(buffer)
              buffer = ""
            rescue ArgumentError
              next
            end
          end

          exit_status = thread.value

          variables = JSON.parse(stdout.read)

          return variables if exit_status.success?
          raise CurlError.new(exit_status.exitstatus, buffer.strip, variables: variables)
        end
      rescue CurlError => e
        http_code = e.variables["http_code"].to_i

        # On a “range not supported” error, try once
        # again after removing the existing file.
        if e.code == 33 || http_code == 416
          if had_incomplete_download
            had_incomplete_download = false
            destination.unlink
            retry
          end
        end

        raise
      end
    end
  end
end
