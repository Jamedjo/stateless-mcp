require "json"
require "rack/request"

module StatelessMcp
  module OAuth
    # The token endpoint as a Rack app. Mount MCP_OAUTH_SERVER.token_app at
    # MCP_OAUTH_SERVER.token_path.
    class TokenEndpoint
      HEADERS = { "content-type" => "application/json", "cache-control" => "no-store", "pragma" => "no-cache" }.freeze

      def initialize(authorization_server)
        @authorization_server = authorization_server
      end

      def call(env)
        return [405, { "allow" => "POST" }, []] unless env["REQUEST_METHOD"] == "POST"
        tokens = @authorization_server.token_request(form(env), authorization: env["HTTP_AUTHORIZATION"]).tokens
        [200, HEADERS.dup, [JSON.generate(tokens)]]
      rescue Error => error
        [error.status, HEADERS.merge(challenge(error, env)), [JSON.generate(error.to_h)]]
      end

      private
        # A 401 names the authentication scheme the client tried, or Basic for
        # a secret in the body (RFC 6749 section 5.2).
        def challenge(error, env)
          return {} unless error.status == 401
          scheme = env["HTTP_AUTHORIZATION"].to_s[/\A[A-Za-z0-9!#$%&'*+.^_`|~-]+/] || "Basic"
          { "www-authenticate" => %(#{scheme} realm="#{@authorization_server.issuer}") }
        end

        def form(env)
          Rack::Request.new(env).POST
        rescue Rack::QueryParser::ParameterTypeError, Rack::QueryParser::InvalidParameterError, Rack::QueryParser::ParamsTooDeepError, EOFError
          raise Error.new("invalid_request", "The request body must be form-encoded")
        end
    end
  end
end
