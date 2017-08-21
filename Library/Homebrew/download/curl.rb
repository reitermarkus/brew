require "download/abstract"

require "open3"

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

    class CurlError < Error
      attr_reader :code

      def initialize(code, message)
        @code = code
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

    def redirect_uri
      redirect_uri, status = Open3.capture2(
        curl_executable, "--silent", "--head", "--write-out", "%{redirect_url}", "-o", "/dev/null", uri.to_s
      )

      return unless status.success?
      return if redirect_uri.empty?

      unless ignore_insecure_redirects
        if uri.to_s.start_with?("https://") && !redirect_uri.start_with?("https://")
          raise InsecureRedirectError, "#{uri} -> #{redirect_uri}"
        end
      end

      self.uri = URI(redirect_uri)
    end

    def thread_routine
      redirect_uri

      path_arguments = destination.directory? ? ["-O"] : ["-o", destination.to_path]

      args = [
        "--progress-bar",
        "--fail",
        "--show-error",
        "--location",
        "--continue-at", "-"
      ]

      destination.dirname.mkpath
      had_incomplete_download = destination.file?

      begin
        Open3.popen3(curl_executable, *args, uri.to_s, *path_arguments) do |stdin, stdout, stderr, thread|
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

          return if exit_status.success?
          raise CurlError.new(exit_status.exitstatus, buffer.strip)
        end
      rescue CurlError => e
        # On a “range not supported” error, try once
        # again after removing the existing file.
        if e.code == 33 && had_incomplete_download
          had_incomplete_download = false
          destination.unlink
          retry
        end

        raise
      end
    end
  end
end
