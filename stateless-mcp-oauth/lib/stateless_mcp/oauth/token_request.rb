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
          storage, claims = read(@params["code"], :code)
          request = claims.authorization_request
          refuse_grant("The authorization code was issued to another client") unless request[:client_id] == @params["client_id"]
          refuse_grant("redirect_uri doesn't match the authorization request") unless request[:redirect_uri] == @params["redirect_uri"]
          refuse_grant("code_verifier doesn't match the code_challenge") unless Pkce.verified?(@params["code_verifier"], request[:code_challenge])
          protected_resource = resource_for(request[:resource])
          refuse_grant("The authorization code wasn't issued for the MCP server it names") unless protected_resource.storage.equal?(storage)
          approved = { client_id: request[:client_id], resource: protected_resource.resource, scope: request[:scope] }
          grant_id = storage.create_grant(code_id: claims.id, authorization_request: approved, approved_by: claims.approved_by)
          unless grant_id
            storage.revoke_grant_for_code(claims.id)
            refuse_grant("The authorization code has already been used")
          end
          response(storage, grant_id, request[:scope])
        end

        # Each refresh token can be used once. If a used refresh token is sent
        # again, two parties must have a copy, so the grant is revoked for both.
        # The used refresh token is consumed before new tokens are issued, so a
        # failure in between never leaves two working refresh tokens.
        def refresh
          storage, claims, raw = read(@params["refresh_token"], :refresh)
          grant = storage.find_grant(claims.grant_id) or refuse_grant("The refresh token's grant has been revoked")
          refuse_grant("The refresh token was issued to another client") unless grant.client_id == @params["client_id"]
          resource_for(grant.resource)
          raise Error.new("invalid_scope", "A refresh can't change the scope") unless @params["scope"].nil? || @params["scope"].split.sort == grant.scope.to_s.split.sort
          unless storage.consume_refresh_token(raw) == true
            storage.revoke_grant(claims.grant_id)
            refuse_grant("The refresh token has already been used")
          end
          response(storage, claims.grant_id, grant.scope)
        end

        # Returns the storage that issued a token, the token's claims, and the
        # hash from read_token, including any keys the storage added. Each
        # protected resource's storage is tried in turn.
        def read(token, kind)
          refuse_grant("#{kind == :code ? "code" : "refresh_token"} is required") if token.to_s.empty?
          @authorization_server.protected_resources.map(&:storage).uniq.each do |storage|
            raw = Claims.symbolize(storage.read_token(token)) or next
            claims = Claims.from_h(raw) or next
            next unless claims.kind == kind
            refuse_grant("The #{kind == :code ? "authorization code" : "refresh token"} has expired") if claims.expired?
            return [storage, claims, raw]
          end
          refuse_grant("The #{kind == :code ? "authorization code" : "refresh token"} isn't one this server issued")
        end

        # The protected resource a grant is for. If the request has a resource
        # parameter, it must name the same protected resource.
        def resource_for(resource)
          protected_resource = @authorization_server.protected_resource(resource) or refuse_grant("The grant is for an MCP server this OAuth server doesn't protect")
          raise Error.new("invalid_target", "resource must be #{protected_resource.resource}") unless @params["resource"].nil? || @authorization_server.protected_resource(@params["resource"]).equal?(protected_resource)
          protected_resource
        end

        def response(storage, grant_id, scope)
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
