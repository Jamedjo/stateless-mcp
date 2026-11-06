require "uri"

module StatelessMcp
  module OAuth
    # The app's OAuth server. It signs people in for MCP clients and issues the
    # clients' tokens. The app creates one, listing the MCP servers it protects:
    #
    #   MCP_OAUTH_SERVER = StatelessMcp::OAuth::AuthorizationServer.new(
    #     issuer: "https://notes.example",
    #     protected_resources: [MCP_OAUTH]
    #   )
    #
    # MCP clients don't register. A client's client_id is the URL of its client
    # metadata document. The server fetches and checks that document.
    class AuthorizationServer
      METADATA_PATH = "/.well-known/oauth-authorization-server".freeze
      GRANT_TYPES = %w[authorization_code refresh_token].freeze

      attr_reader :issuer, :protected_resources, :scopes, :authorization_path, :token_path, :code_ttl, :client_metadata_transport, :client_metadata_cache, :localhost_redirects

      # issuer is the server's origin, such as "https://notes.example".
      # protected_resources are the StatelessMcp::OAuth::ProtectedResource
      # objects it issues tokens for. Each one's authorization_server must equal
      # issuer.
      #
      # code_ttl is how many seconds an authorization code lasts.
      #
      # client_metadata_transport makes the connection when a client's metadata
      # document is fetched. It defaults to a DocumentTransport, which needs the
      # ssrf_filter gem. DocumentFetcher's rules apply whatever it is.
      # client_metadata_cache defaults to a MemoryCache in this
      # process. Any object that responds to read(key) and
      # write(key, value, expires_in:), such as Rails.cache, can replace the
      # cache.
      #
      # localhost_redirects: false accepts only 127.0.0.1 and [::1] as loopback
      # redirect URIs. See ClientMetadata.fetch.
      def initialize(issuer:, protected_resources:, authorization_path: "/oauth/authorize", token_path: "/oauth/token", code_ttl: 120, client_metadata_transport: nil, client_metadata_cache: nil, localhost_redirects: true)
        @issuer = origin(issuer)
        @protected_resources = Array(protected_resources).freeze
        raise ArgumentError, "protected_resources must list at least one StatelessMcp::OAuth::ProtectedResource" if @protected_resources.empty?
        @protected_resources.each do |protected_resource|
          raise ArgumentError, "#{protected_resource.resource} names #{protected_resource.authorization_server} as its authorization server, not #{@issuer}" unless protected_resource.authorization_server == @issuer
        end
        @scopes = @protected_resources.flat_map(&:scopes).uniq.freeze
        @authorization_path = path(authorization_path, "authorization_path")
        @token_path = path(token_path, "token_path")
        raise ArgumentError, "code_ttl must be a positive number of seconds; got #{code_ttl.inspect}" unless code_ttl.is_a?(Integer) && code_ttl.positive?
        @code_ttl = code_ttl
        @client_metadata_transport = client_metadata_transport || DocumentTransport.new
        @client_metadata_cache = client_metadata_cache || MemoryCache.new
        @localhost_redirects = localhost_redirects ? true : false
        freeze
      end

      def authorization_endpoint
        "#{issuer}#{authorization_path}"
      end

      def token_endpoint
        "#{issuer}#{token_path}"
      end

      # The ProtectedResource for a resource URL from a client, or nil. The
      # scheme and host are compared case-insensitively, as the MCP spec
      # requires. The rest of the URL must match exactly.
      def protected_resource(resource)
        wanted = canonical(resource) or return nil
        protected_resources.find { |protected_resource| canonical(protected_resource.resource) == wanted }
      end

      # A client's request to sign a person in, from the authorization
      # endpoint's params, as a StatelessMcp::OAuth::AuthorizationRequest.
      # Raises StatelessMcp::OAuth::Error when the client or its redirect_uri
      # can't be trusted.
      def authorization_request(params)
        AuthorizationRequest.new(params, authorization_server: self)
      end

      # The client's metadata document, fetched from its client_id and checked,
      # as a StatelessMcp::OAuth::ClientMetadata. Raises
      # StatelessMcp::OAuth::Error for a client_id or document that fails the
      # checks.
      def client(client_id)
        ClientMetadata.fetch(client_id, transport: client_metadata_transport, cache: client_metadata_cache, localhost_redirects: localhost_redirects)
      end

      # The authorization server metadata (RFC 8414). A client reads it after
      # the protected resource metadata. client_id_metadata_document_supported
      # means a client uses its metadata document's URL as its client_id. The
      # metadata lists "none" as the only token endpoint auth method, and has
      # no registration endpoint.
      def metadata
        {
          issuer: issuer,
          authorization_endpoint: authorization_endpoint,
          token_endpoint: token_endpoint,
          response_types_supported: ["code"],
          response_modes_supported: ["query"],
          grant_types_supported: GRANT_TYPES,
          code_challenge_methods_supported: ["S256"],
          token_endpoint_auth_methods_supported: ["none"],
          scopes_supported: (scopes unless scopes.empty?),
          client_id_metadata_document_supported: true,
          authorization_response_iss_parameter_supported: true
        }.compact
      end

      def metadata_path
        METADATA_PATH
      end

      # A Rack app that serves the metadata, for mounting at metadata_path.
      def metadata_app
        MetadataApp.new(metadata)
      end

      def inspect
        "#<#{self.class.name} #{issuer}>"
      end

      private
        def origin(url)
          uri = URI(url.to_s)
          local = uri.scheme == "http" && %w[localhost 127.0.0.1].include?(uri.host)
          return url.to_s.dup.freeze if uri.host && (uri.scheme == "https" || local) && uri.path.empty? && uri.query.nil? && uri.fragment.nil? && uri.userinfo.nil?
          raise ArgumentError, "issuer must be an https origin, such as \"https://notes.example\", with no path; got #{url.inspect}"
        rescue URI::InvalidURIError
          raise ArgumentError, "issuer must be an https origin, such as \"https://notes.example\", with no path; got #{url.inspect}"
        end

        def canonical(url)
          uri = URI(url.to_s)
          uri.normalize.to_s if uri.is_a?(URI::HTTP) && uri.host && uri.fragment.nil?
        rescue URI::InvalidURIError
          nil
        end

        def path(value, name)
          raise ArgumentError, "#{name} must be a path starting with /; got #{value.inspect}" unless value.is_a?(String) && value.match?(%r{\A/[A-Za-z0-9\-._~/]*\z})
          value.dup.freeze
        end
    end
  end
end
