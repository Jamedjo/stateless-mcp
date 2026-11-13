module StatelessMcp
  module OAuth
    # Rack middleware for Rack and Sinatra apps. It goes before
    # StatelessMcp::Middleware, with the same server:
    #
    #   use StatelessMcp::OAuth::RequireToken, protected_resource: MCP_OAUTH, server: SERVER
    #   use StatelessMcp::Middleware, server: SERVER
    #
    # - A request to the server's endpoint needs a valid access token. It
    #   reaches the app with its grant in env["stateless_mcp.oauth.grant"], or
    #   gets a 401 that points the client at the metadata.
    # - A request to the metadata path gets the protected resource metadata.
    # - Other requests pass through.
    #
    # The endpoint check is the server's own, so every request the MCP
    # middleware handles has been through this one first.
    class RequireToken
      GRANT = "stateless_mcp.oauth.grant".freeze

      def initialize(app, protected_resource:, server:)
        raise ArgumentError, "server: must be a StatelessMcp::Server; got #{server.inspect}" unless server.is_a?(StatelessMcp::Server)
        @app = app
        @protected_resource = protected_resource
        @server = server
        @metadata_app = protected_resource.metadata_app
      end

      def call(env)
        return @metadata_app.call(env) if env["PATH_INFO"] == @protected_resource.metadata_path
        return @app.call(env) unless @server.endpoint?(env)

        grant = @protected_resource.verified_grant(env) or return unauthorized(env)
        env[GRANT] = grant
        @app.call(env)
      end

      private
        def unauthorized(env)
          [401, @protected_resource.unauthorized_headers(invalid_token: env.key?("HTTP_AUTHORIZATION")), []]
        end
    end
  end
end
