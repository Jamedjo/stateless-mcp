require "digest"
require "json"
require "uri"

module StatelessMcp
  module OAuth
    # A client's metadata document, fetched from its client_id and validated.
    # Only public clients are accepted. Anyone can read the document, so it
    # can't contain a client secret. Each client uses PKCE instead.
    class ClientMetadata
      LOOPBACK_IPS = ["127.0.0.1", "[::1]"].freeze
      LOOPBACK_HOSTS = (LOOPBACK_IPS + ["localhost"]).freeze
      MAX_NAME_LENGTH = 80
      DEFAULT_TTL = 300
      TTL_RANGE = (60..86_400)

      attr_reader :client_id, :name, :redirect_uris

      # The client's document, read from the cache until the entry expires.
      # Only a document that passes the checks is cached. It's kept for as long
      # as its Cache-Control header allows, between a minute and a day.
      #
      # transport is a DocumentTransport, or a replacement. DocumentFetcher's
      # rules apply whichever it is.
      # cache responds to read(key) and write(key, value, expires_in:), as a
      # MemoryCache or Rails.cache does.
      #
      # localhost_redirects: false accepts only 127.0.0.1 and [::1] as loopback
      # redirect URIs, as RFC 8252 advises, since a name can resolve elsewhere.
      # It refuses a document that lists http://localhost. The default accepts
      # localhost too, since Claude Code and Cursor redirect to it.
      def self.fetch(client_id, transport:, cache:, localhost_redirects: true)
        ClientId.check!(client_id)
        key = "stateless_mcp/oauth/client_metadata/#{Digest::SHA256.hexdigest(client_id)}"
        cached = cache.read(key)
        return parse(client_id, cached, localhost_redirects: localhost_redirects) if cached
        body, cache_control = download(transport, client_id)
        parse(client_id, body, localhost_redirects: localhost_redirects).tap do
          ttl = ttl(cache_control)
          cache.write(key, body, expires_in: ttl) if ttl
        end
      end

      def self.parse(client_id, body, localhost_redirects: true)
        document = JSON.parse(body.to_s)
        refuse("The client metadata document must be a JSON object") unless document.is_a?(Hash)
        new(client_id, document, localhost_redirects: localhost_redirects)
      rescue JSON::ParserError
        refuse("The client metadata document isn't JSON")
      end

      def self.ttl(cache_control)
        directives = cache_control.to_s.downcase.split(",").map(&:strip)
        return nil if directives.intersect?(["no-store", "no-cache", "private"])
        max_age = directives.filter_map { |directive| directive[/\Amax-age=(\d+)\z/, 1] }.first
        return nil if max_age == "0"
        (max_age ? max_age.to_i : DEFAULT_TTL).clamp(TTL_RANGE.begin, TTL_RANGE.end)
      end

      def self.download(transport, client_id)
        DocumentFetcher.new(transport).get(client_id)
      rescue DocumentFetcher::Failed
        refuse("Couldn't load the client's metadata document from #{URI.parse(client_id).host}")
      end

      # An http URL to this computer, where a native app listens.
      def self.loopback?(value, hosts = LOOPBACK_HOSTS)
        uri = URI.parse(value)
        uri.scheme == "http" && hosts.include?(uri.host)
      rescue URI::InvalidURIError, TypeError
        false
      end

      def self.refuse(message)
        raise Error.new("invalid_client", message, redirectable: false)
      end

      private_class_method :download

      def initialize(client_id, document, localhost_redirects: true)
        @client_id = client_id
        @loopback_hosts = localhost_redirects ? LOOPBACK_HOSTS : LOOPBACK_IPS
        self.class.refuse("The client metadata document names a different client_id") unless document["client_id"] == client_id
        @name = document["client_name"].to_s.gsub(/[[:space:][:cntrl:]]+/, " ").strip[0, MAX_NAME_LENGTH]
        self.class.refuse("The client metadata document has no client_name") if @name.empty?
        @redirect_uris = document["redirect_uris"]
        self.class.refuse("The client metadata document needs redirect_uris, each https or loopback") unless valid_redirect_uris?
        self.class.refuse("Only public clients, with token_endpoint_auth_method none, can connect") unless public_client?(document)
        self.class.refuse("The client metadata document must allow the authorization code flow") unless authorization_code_flow?(document)
        freeze
      end

      def host
        URI.parse(client_id).host
      end

      # Compares redirect URIs exactly, except for the port of a loopback
      # redirect URI. A native app listens on whichever port is free (OAuth 2.1
      # section 8.4.2).
      def redirect_uri?(candidate)
        return false unless candidate.is_a?(String)
        redirect_uris.include?(candidate) || (loopback?(candidate) && redirect_uris.any? { |registered| loopback?(registered) && same_ignoring_port?(registered, candidate) })
      end

      # An http URL to this computer, naming one of the loopback hosts.
      def loopback?(value)
        self.class.loopback?(value, @loopback_hosts)
      end

      private

      def valid_redirect_uris?
        redirect_uris.is_a?(Array) && !redirect_uris.empty? && redirect_uris.all? { |uri| valid_redirect_uri?(uri) }
      end

      def valid_redirect_uri?(value)
        uri = URI.parse(value)
        !uri.host.to_s.empty? && uri.fragment.nil? && uri.userinfo.nil? && (uri.scheme == "https" || loopback?(value))
      rescue URI::InvalidURIError, TypeError
        false
      end

      def same_ignoring_port?(registered, candidate)
        URI.parse(registered).tap { |uri| uri.port = nil }.to_s == URI.parse(candidate).tap { |uri| uri.port = nil }.to_s
      end

      # A client secret in a published document isn't secret. private_key_jwt
      # would need the client's keys fetched too, which isn't supported.
      def public_client?(document)
        [nil, "none"].include?(document["token_endpoint_auth_method"]) && !document.key?("client_secret")
      end

      def authorization_code_flow?(document)
        Array(document["grant_types"] || ["authorization_code"]).include?("authorization_code") && Array(document["response_types"] || ["code"]).include?("code")
      end
    end
  end
end
