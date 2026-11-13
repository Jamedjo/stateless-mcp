require "securerandom"

module StatelessMcp
  module OAuth
    # A request to the token endpoint. It exchanges an authorization code or a
    # refresh token for new tokens. tokens returns the token response as a
    # hash. If a check fails, tokens raises an Error, which the token endpoint
    # returns as the response.
    #
    # Clients are public and have no client secret. An authorization code is
    # exchanged only with the PKCE code verifier that matches its
    # authorization request's code challenge.
    class TokenRequest
      PARAMS = %w[grant_type code code_verifier redirect_uri client_id refresh_token resource scope].freeze

      attr_reader :params

      # Only string values are read, so a parameter sent as an array or a hash
      # counts as missing. authorization is the request's Authorization header.
      def initialize(params, authorization_server:, authorization: nil)
        @params = PARAMS.to_h { |name| [name, params[name]] }.select { |_name, value| value.is_a?(String) }.freeze
        @authorization_server = authorization_server
        raise Error.new("invalid_client", "Clients authenticate with PKCE, not a secret", status: 401) if params.key?("client_secret") || params.key?("client_assertion") || !authorization.to_s.empty?
        raise Error.new("unsupported_grant_type", "grant_type must be authorization_code or refresh_token") unless AuthorizationServer::GRANT_TYPES.include?(@params["grant_type"])
        raise Error.new("invalid_request", "client_id is required") if @params["client_id"].to_s.empty?
      end

      def tokens
        @params["grant_type"] == "authorization_code" ? exchange_code : refresh
      end

      private
        # Every check comes before create_grant, so someone without the PKCE
        # verifier can't use up another client's authorization code.
        def exchange_code
          claims = read(@params["code"], :code).first
          request = claims.authorization_request
          refuse_grant("The authorization code was issued to another client") unless request[:client_id] == @params["client_id"]
          refuse_grant("redirect_uri doesn't match the authorization request") unless request[:redirect_uri] == @params["redirect_uri"]
          refuse_grant("code_verifier doesn't match the code_challenge") unless Pkce.verified?(@params["code_verifier"], request[:code_challenge])
          same_resource!(request[:resource])
          approved = { client_id: request[:client_id], resource: protected_resource.resource, scope: request[:scope] }
          grant_id = storage.create_grant(code_id: claims.id, authorization_request: approved, approved_by: claims.approved_by)
          unless grant_id
            storage.revoke_grant_for_code(claims.id)
            refuse_grant("The authorization code has already been used")
          end
          response(grant_id, request[:scope])
        end

        # Each refresh token can be used once. If a used refresh token is sent
        # again, two parties must have a copy, so the grant is revoked for both.
        # The used refresh token is consumed before new tokens are issued, so a
        # failure in between never leaves two working refresh tokens.
        def refresh
          claims, raw = read(@params["refresh_token"], :refresh)
          grant = storage.find_grant(claims.grant_id) or refuse_grant("The refresh token's grant has been revoked")
          refuse_grant("The refresh token was issued to another client") unless grant.client_id == @params["client_id"]
          same_resource!(grant.resource)
          raise Error.new("invalid_scope", "A refresh can't change the scope") unless @params["scope"].nil? || @params["scope"].split.sort == grant.scope.to_s.split.sort
          unless storage.consume_refresh_token(raw) == true
            storage.revoke_grant(claims.grant_id)
            refuse_grant("The refresh token has already been used")
          end
          response(claims.grant_id, grant.scope)
        end

        # The MCP server the request is for, named by its resource parameter
        # (RFC 8707), which the MCP spec has clients send with every token
        # request. A client may leave it out only when the OAuth server protects
        # a single MCP server. Its storage issued the tokens being exchanged.
        def protected_resource
          @protected_resource ||= if @params.key?("resource")
            @authorization_server.protected_resource(@params["resource"]) or raise Error.new("invalid_target", "resource must be one of: #{@authorization_server.protected_resources.map(&:resource).join(" ")}")
          elsif @authorization_server.protected_resources.one?
            @authorization_server.protected_resources.first
          else
            raise Error.new("invalid_target", "resource is required, as this OAuth server protects several MCP servers")
          end
        end

        def storage
          protected_resource.storage
        end

        # Returns a token's claims, and the hash from read_token, including any
        # keys the storage added.
        def read(token, kind)
          refuse_grant("#{kind == :code ? "code" : "refresh_token"} is required") if token.to_s.empty?
          raw = Claims.symbolize(storage.read_token(token))
          claims = Claims.from_h(raw) if raw
          refuse_grant("The #{kind == :code ? "authorization code" : "refresh token"} isn't one this server issued") unless claims&.kind == kind
          refuse_grant("The #{kind == :code ? "authorization code" : "refresh token"} has expired") if claims.expired?
          [claims, raw]
        end

        # The authorization code or grant must be for the MCP server the request
        # names.
        def same_resource!(resource)
          raise Error.new("invalid_target", "resource must be #{resource}") unless @authorization_server.protected_resource(resource).equal?(protected_resource)
        end

        def response(grant_id, scope)
          now = Time.now.to_i
          access = Claims.new(kind: :access, id: SecureRandom.uuid, grant_id: grant_id, expires_at: now + @authorization_server.access_token_ttl)
          refresh = Claims.new(kind: :refresh, id: SecureRandom.uuid, grant_id: grant_id, expires_at: now + @authorization_server.refresh_token_ttl)
          access_token, refresh_token = storage.issue_tokens(access.to_h, refresh.to_h)
          { access_token: access_token, token_type: "Bearer", expires_in: @authorization_server.access_token_ttl, refresh_token: refresh_token, scope: (scope unless scope.to_s.empty?) }.compact
        end

        def refuse_grant(message)
          raise Error.new("invalid_grant", message)
        end
    end
  end
end
