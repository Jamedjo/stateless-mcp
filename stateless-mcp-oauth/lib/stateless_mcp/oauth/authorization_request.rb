require "securerandom"
require "uri"

module StatelessMcp
  module OAuth
    # A client's request to sign a person in, from the authorization endpoint's
    # query string. The app's consent page shows it, and the person approves or
    # denies it:
    #
    #   authorization = MCP_OAUTH_SERVER.authorization_request(params)
    #   return redirect_to(authorization.error_redirect_url, allow_other_host: true) if authorization.problem
    #   # On the consent page's approval:
    #   redirect_to authorization.approve(user_id: current_user.id), allow_other_host: true
    #
    # The checks follow RFC 6749 section 4.1.2.1:
    # - If the client or its redirect_uri can't be trusted, new raises an
    #   Error. The app shows that error to the person, and doesn't redirect.
    # - Otherwise, problem returns the first other error, or nil.
    #   error_redirect_url sends it to the client's redirect_uri.
    #
    # Nothing is stored until approve, so showing the consent page is safe on a
    # GET.
    class AuthorizationRequest
      PARAMS = %w[response_type client_id redirect_uri code_challenge code_challenge_method state scope resource].freeze
      MAX_STATE_LENGTH = 1024

      attr_reader :params, :client, :redirect_uri

      # Raises an Error that isn't redirectable when the client or its
      # redirect_uri can't be trusted.
      def initialize(params, authorization_server:)
        @params = PARAMS.to_h { |name| [name, params[name]] }.select { |_name, value| value.is_a?(String) }.freeze
        @authorization_server = authorization_server
        @client = authorization_server.client(@params["client_id"])
        @redirect_uri = @params["redirect_uri"]
        raise Error.new("invalid_request", "redirect_uri isn't one #{client.host} listed", redirectable: false) unless client.redirect_uri?(redirect_uri)
      end

      # The first error to report to the client, as an Error, or nil.
      def problem
        return Error.new("unsupported_response_type", "response_type must be code") unless params["response_type"] == "code"
        return Error.new("invalid_request", "code_challenge_method must be S256") unless params["code_challenge_method"] == Pkce::METHOD
        return Error.new("invalid_request", "code_challenge must be an S256 challenge") unless Pkce.challenge?(params["code_challenge"])
        return Error.new("invalid_request", "state is too long") if state.to_s.length > MAX_STATE_LENGTH
        return Error.new("invalid_target", "resource must be one of: #{@authorization_server.protected_resources.map(&:resource).join(" ")}") unless protected_resource
        Error.new("invalid_scope", "scope must include one of: #{protected_resource.scopes.join(" ")}") if scopes.empty? && protected_resource.scopes.any?
      end

      def state
        params["state"]
      end

      # The MCP server named by the resource parameter. A client may leave out
      # resource only when the OAuth server protects a single MCP server.
      def protected_resource
        resources = @authorization_server.protected_resources
        params.key?("resource") ? @authorization_server.protected_resource(params["resource"]) : (resources.first if resources.one?)
      end

      # The requested scopes that the MCP server supports. Unknown scopes are
      # dropped. If the client requested none, the MCP server's default_scopes,
      # so a client never gets more than the app chose.
      def scopes
        return [] unless protected_resource
        requested = params["scope"].to_s.split
        requested.empty? ? protected_resource.default_scopes : requested & protected_resource.scopes
      end

      # The redirect URI's host, which a consent page should show.
      def redirect_host
        URI(redirect_uri).host
      end

      # True when the redirect URI is a loopback address. Any app on the
      # person's computer could be listening on a loopback port, so a consent
      # page should warn the person.
      def loopback_redirect?
        client.loopback?(redirect_uri)
      end

      # Issues an authorization code through the MCP server's storage. Returns
      # the URL that sends the person back to the client with that
      # authorization code. approved_by holds the app's attributes for who
      # approved, such as user_id: current_user.id. They're passed to
      # create_grant when the authorization code is exchanged.
      def approve(**approved_by)
        raise ArgumentError, "Can't approve an authorization request with a problem: #{problem.message}" if problem
        request = { client_id: client.client_id, redirect_uri: redirect_uri, code_challenge: params["code_challenge"], scope: scopes.join(" "), resource: protected_resource.resource }
        claims = Claims.new(kind: :code, id: SecureRandom.uuid, expires_at: Time.now.to_i + @authorization_server.code_ttl, authorization_request: request, approved_by: approved_by)
        redirect_url(code: protected_resource.storage.issue_token(claims.to_h))
      end

      # The URL to send the person back to the client when they deny it.
      def deny
        redirect_url(error: "access_denied")
      end

      # The URL to send the person back to the client with problem.
      def error_redirect_url(error = problem)
        redirect_url(error: error.code, error_description: error.message)
      end

      private
        # Every redirect includes the iss parameter, errors included (RFC 9207).
        # A client that uses several OAuth servers can then check which one
        # responded.
        def redirect_url(response)
          uri = URI(redirect_uri)
          query = URI.decode_www_form(uri.query.to_s) + response.merge(state: state, iss: @authorization_server.issuer).compact.map { |key, value| [key.to_s, value] }
          uri.query = URI.encode_www_form(query)
          uri.to_s
        end
    end
  end
end
