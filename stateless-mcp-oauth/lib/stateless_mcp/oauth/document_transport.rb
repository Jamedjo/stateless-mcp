require "ipaddr"
require "net/http"
require "resolv"
require "uri"

module StatelessMcp
  module OAuth
    # Makes the connection when a client metadata document is fetched, and
    # decides where it may go. DocumentFetcher applies the rules for what comes
    # back, whatever the transport.
    #
    # By default the ssrf_filter gem resolves the host, refuses private,
    # loopback, link-local and cloud metadata addresses, and connects to the
    # address it checked, so DNS can't switch it afterwards.
    #
    # - proxy: sends the fetch through an egress proxy, such as Smokescreen.
    #   The proxy resolves the host and makes the connection, so ssrf_filter's
    #   checks don't apply. The proxy must refuse internal addresses itself.
    # - deny_networks: address ranges refused on top of ssrf_filter's, such as
    #   "100.64.0.0/10". Not with proxy:, since the proxy resolves the host.
    # - headers: extra request headers. They can't replace the Accept and
    #   Accept-Encoding headers DocumentFetcher sends.
    #
    # Another object can replace it. Its call(url, headers:, timeout:) must
    # send headers, never follow a redirect, and never decompress. It yields
    # the status, the headers as a Hash with lowercase names, and a body whose
    # each yields it in chunks as they arrive. It raises
    # DocumentFetcher::Failed when it can't connect.
    class DocumentTransport
      ResponseBody = Struct.new(:response) do
        def each(&block)
          response.read_body(&block)
        end
      end

      def initialize(proxy: nil, deny_networks: [], headers: {}, resolver: nil)
        @proxy = proxy && URI(proxy)
        @deny_networks = deny_networks.map { |network| IPAddr.new(network) }.freeze
        raise ArgumentError, "deny_networks: can't apply through a proxy, which resolves the host itself. Refuse those ranges in the proxy" if @proxy && @deny_networks.any?
        @headers = headers.to_h { |name, value| [name.to_s.downcase, value.to_s] }.freeze
        @resolver = resolver || method(:resolve)
        load_ssrf_filter unless @proxy
        freeze
      end

      def call(url, headers:, timeout:, &block)
        headers = @headers.merge(headers)
        @proxy ? through_proxy(URI(url), headers, timeout, &block) : direct(url, headers, timeout, &block)
      rescue DocumentFetcher::Failed
        raise
      rescue StandardError => error
        raise unless network_error?(error)
        raise DocumentFetcher::Failed, "#{error.class}: #{error.message}"
      end

      private
        def direct(url, headers, timeout, &block)
          SsrfFilter.get(url, scheme_whitelist: ["https"], max_redirects: 0, allow_unfollowed_redirects: true, resolver: ->(host) { allowed(@resolver.call(host, timeout)) }, headers: headers, http_options: http_options(timeout)) do |response|
            respond(response, &block)
          end
        end

        def through_proxy(uri, headers, timeout, &block)
          raise DocumentFetcher::Failed, "not an https URL" unless uri.is_a?(URI::HTTPS)
          Net::HTTP.start(uri.hostname, uri.port, @proxy.hostname, @proxy.port, @proxy.user, @proxy.password, use_ssl: true, **http_options(timeout)) do |http|
            http.request(Net::HTTP::Get.new(uri, headers)) { |response| respond(response, &block) }
          end
        end

        # Net::HTTP would decompress before DocumentFetcher's size check, so a
        # small compressed body could still fill memory.
        def respond(response)
          response.decode_content = false
          yield response.code.to_i, response.to_hash.transform_values { |values| values.join(", ") }, ResponseBody.new(response)
        end

        def allowed(addresses)
          allowed = addresses.reject { |address| @deny_networks.any? { |network| network.include?(address) } }
          raise DocumentFetcher::Failed, "resolves only to denied addresses" if allowed.empty? && addresses.any?
          allowed
        end

        def http_options(timeout)
          { open_timeout: timeout, read_timeout: timeout, ssl_timeout: timeout, write_timeout: timeout }
        end

        # Name lookups are held to the same timeout as the rest.
        def resolve(hostname, timeout)
          dns = Resolv::DNS.new.tap { |resolver| resolver.timeouts = timeout }
          Resolv.new([Resolv::Hosts.new, dns]).getaddresses(hostname).map { |address| IPAddr.new(address) }
        end

        def network_error?(error)
          [SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Timeout::Error, Net::HTTPBadResponse, Net::ProtocolError, Resolv::ResolvError].any? { |type| error.is_a?(type) } ||
            (defined?(SsrfFilter::Error) && error.is_a?(SsrfFilter::Error))
        end

        def load_ssrf_filter
          require "ssrf_filter"
        rescue LoadError
          raise ArgumentError, "Client metadata documents are fetched through the ssrf_filter gem by default. Add gem \"ssrf_filter\" to the Gemfile, or fetch through an egress proxy with proxy:"
        end
    end
  end
end
