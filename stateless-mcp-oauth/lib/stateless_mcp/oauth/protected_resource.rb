require "json"
require "uri"

module StatelessMcp
  module OAuth
    # An MCP server whose requests need an access token. OAuth calls it a
    # protected resource (RFC 9728). The app makes one, and checks each MCP
    # request with verified_grant:
    #
    #   MCP_OAUTH = StatelessMcp::OAuth::ProtectedResource.new(
    #     resource: "https://notes.example/mcp",
    #     authorization_server: "https://notes.example",
    #     storage: McpOAuthStorage.new
    #   )
    class ProtectedResource
      # Far longer than any token a storage class issues.
      MAX_HEADER = 4096

      attr_reader :resource, :authorization_server, :storage, :scopes

      # resource is the MCP server's URL, which clients name when they sign in.
      # authorization_server is the URL of the OAuth server that issues its
      # tokens. scopes are the scopes a client can ask for.
      def initialize(resource:, authorization_server:, storage:, scopes: [])
        @resource = absolute_url(resource, "resource")
        @authorization_server = absolute_url(authorization_server, "authorization_server")
        @storage = storage
        @scopes = scopes.map(&:to_s).freeze
        freeze
      end

      # Returns the grant behind a request's access token, from the storage's
      # find_grant. Returns nil if the request has no access token, or if the
      # token is unknown, revoked, expired, not an access token, or for another
      # MCP server. Takes a Rack request, or a Rack env.
      def verified_grant(request)
        verified_grant!(request)
      rescue InvalidToken
        nil
      end

      # Like verified_grant, but raises InvalidToken with the reason a token
      # was refused, for the app's logs and metrics.
      def verified_grant!(request)
        token = bearer_token(request.respond_to?(:env) ? request.env : request) or raise InvalidToken.new(:missing)
        claims = Claims.from_h(storage.read_token(token)) or raise InvalidToken.new(:unknown)
        raise InvalidToken.new(:not_an_access_token) unless claims.kind == :access
        raise InvalidToken.new(:expired) if claims.expired?
        grant = storage.find_grant(claims.grant_id) or raise InvalidToken.new(:revoked)
        raise InvalidToken.new(:other_mcp_server) unless grant.resource == resource
        grant
      end

      # The headers for a 401 response: a WWW-Authenticate header with the
      # Bearer scheme (RFC 6750 section 3). Its resource_metadata parameter
      # points the client at the metadata, which says where to sign in (RFC 9728
      # section 5.1, which the MCP spec requires). invalid_token is for a
      # request that sent a token verified_grant didn't accept.
      def unauthorized_headers(invalid_token: false)
        value = %(Bearer resource_metadata="#{metadata_url}")
        value += %(, error="invalid_token") if invalid_token
        { "www-authenticate" => value }
      end

      # The protected resource metadata a client reads after a 401 (RFC 9728
      # section 2).
      def metadata
        { resource: resource, authorization_servers: [authorization_server], scopes_supported: scopes, bearer_methods_supported: ["header"] }
      end

      # Where the metadata is served: /.well-known/oauth-protected-resource,
      # then the MCP server's path, as RFC 9728 places it.
      def metadata_path
        "/.well-known/oauth-protected-resource#{URI(resource).path.chomp("/")}"
      end

      def metadata_url
        URI.join(resource, metadata_path).to_s
      end

      # A Rack app that serves the metadata, for mounting at metadata_path.
      def metadata_app
        MetadataApp.new(metadata)
      end

      private
        # The token from an Authorization: Bearer header, as RFC 6750 gives
        # it. MCP clients never send one in the query string.
        def bearer_token(env)
          header = env["HTTP_AUTHORIZATION"].to_s
          header[/\ABearer +([A-Za-z0-9\-._~+\/]+=*) *\z/i, 1] if header.length <= MAX_HEADER
        end

        def absolute_url(url, name)
          uri = URI(url.to_s)
          raise ArgumentError, "#{name} must be an https URL, or http on localhost; got #{url.inspect}" unless uri.host && (uri.scheme == "https" || (uri.scheme == "http" && %w[localhost 127.0.0.1].include?(uri.host)))
          raise ArgumentError, "#{name} must not have a query or fragment; got #{url.inspect}" if uri.query || uri.fragment
          uri.to_s.freeze
        rescue URI::InvalidURIError
          raise ArgumentError, "#{name} must be a URL; got #{url.inspect}"
        end
    end
  end
end
