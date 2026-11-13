module StatelessMcp
  module OAuth
    # Rack middleware for Rack and Sinatra apps. It goes before
    # StatelessMcp::Middleware, with the same server:
    #
    #   use StatelessMcp::OAuth::RequireToken, protected_resource: MCP_OAUTH, server: SERVER
    #   use StatelessMcp::Middleware, server: SERVER
    #
    # - A POST to the server's endpoint needs a valid access token. It reaches
    #   the app with its grant in env["stateless_mcp.oauth.grant"], or gets a
    #   401 that points the client at the metadata. Coming first, the 401
    #   reaches a client whatever else is wrong with its request, so it always
    #   learns where to sign in.
    # - A request to the metadata path gets the protected resource metadata.
    # - Other requests pass through, so GET and DELETE get the MCP
    #   middleware's 405.
    #
    # protected_resource can be a lambda, called for each request, for an app
    # that builds it after boot. The endpoint check is the server's own, so
    # every POST the MCP middleware handles has been through this one first.
    class RequireToken
      GRANT = StatelessMcp::GRANT_ENV_KEY

      def initialize(app, protected_resource:, server:)
        raise ArgumentError, "server: must be a StatelessMcp::Server; got #{server.inspect}" unless server.is_a?(StatelessMcp::Server)
        @app = app
        @protected_resource = protected_resource
        @server = server
      end

      def call(env)
        resource = protected_resource
        return resource.metadata_app.call(env) if env["PATH_INFO"] == resource.metadata_path
        return @app.call(env) unless @server.endpoint?(env) && env["REQUEST_METHOD"] == "POST"

        grant = resource.verified_grant(env) or return unauthorized(resource, env)
        env[GRANT] = grant
        @app.call(env)
      end

      private
        def protected_resource
          @protected_resource.respond_to?(:call) ? @protected_resource.call : @protected_resource
        end

        def unauthorized(resource, env)
          [401, resource.unauthorized_headers(invalid_token: env.key?("HTTP_AUTHORIZATION")), []]
        end
    end
  end
end
