require "timeout"
require "uri"

module StatelessMcp
  module OAuth
    # Fetches a client's metadata document from its client_id URL, through a
    # DocumentTransport or a replacement. The client chooses the URL, so these
    # rules hold whatever the transport:
    # - https only, with no redirects.
    # - A 200, served as application/json, so a page that only happens to hold
    #   JSON isn't taken for a client's document.
    # - No compression, a few kilobytes and a few seconds at most.
    class DocumentFetcher
      Failed = Class.new(StandardError)

      HEADERS = { "accept" => "application/json", "accept-encoding" => "identity" }.freeze
      MAX_BYTES = 5120
      TIMEOUT = 3

      def initialize(transport)
        @transport = transport
        freeze
      end

      # Returns the body and its Cache-Control header. The transport's timeouts
      # apply to each read. A server sending one header a second would never
      # trigger them, so an overall deadline applies to the fetch too.
      def get(url)
        raise Failed, "not an https URL" unless https?(url)
        body = +""
        cache_control = nil
        answered = false
        Timeout.timeout(TIMEOUT * 2, Failed, "slower than #{TIMEOUT * 2} seconds") do
          @transport.call(url, headers: HEADERS, timeout: TIMEOUT) do |status, headers, chunks|
            check(status, headers)
            read_capped(chunks, body)
            cache_control = headers["cache-control"]
            answered = true
          end
        end
        raise Failed, "no response" unless answered
        [body, cache_control]
      end

      private
        def https?(url)
          URI(url).is_a?(URI::HTTPS)
        rescue URI::InvalidURIError
          false
        end

        def check(status, headers)
          raise Failed, "status #{status}" unless status == 200
          raise Failed, "not served as JSON, but as #{headers["content-type"].inspect}" unless json?(headers["content-type"])
          raise Failed, "compressed as #{headers["content-encoding"]}" unless [nil, "", "identity"].include?(headers["content-encoding"]&.strip&.downcase)
          raise Failed, "larger than #{MAX_BYTES} bytes" if headers["content-length"].to_i > MAX_BYTES
        end

        def read_capped(chunks, body)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT
          chunks.each do |chunk|
            body << chunk
            raise Failed, "larger than #{MAX_BYTES} bytes" if body.bytesize > MAX_BYTES
            raise Failed, "slower than #{TIMEOUT} seconds" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          end
        end

        def json?(content_type)
          content_type.to_s.split(";").first.to_s.strip.casecmp?("application/json")
        end
    end
  end
end
