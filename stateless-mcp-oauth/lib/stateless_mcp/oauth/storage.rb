module StatelessMcp
  module OAuth
    # The base class for OAuth state. The app subclasses it, and the gem calls
    # its methods. See docs/oauth-storage.md. Check the subclass with
    # StatelessMcp::OAuth::StorageCheck, from the gem's test_support folder.
    #
    # A grant is one person allowing one client to use one MCP server.
    # Authorization codes, access tokens and refresh tokens each belong to a
    # grant. Claims are passed in and returned as hashes with symbol keys.
    #
    # The subclass controls where grants and tokens are kept, what a token
    # string is, and how read_token gets claims back from it. So an app keeps
    # OAuth state in its own database, and encrypts tokens with a library it
    # already trusts, or keeps them as rows.
    #
    # Every method is required except issue_tokens and revoke_token. Each must be atomic. On an
    # error, raise. Never return a wrong value.
    class Storage
      # Records a grant when an authorization code is exchanged, and returns
      # the new grant's id as a String.
      #
      # - authorization_request: what the client asked for and the person
      #   approved, as { client_id:, resource:, scope: }.
      # - approved_by: the attributes the app chose for who approved, such as
      #   { user_id: 42 }.
      #
      # Returns nil, changing nothing, for a code_id it has seen before, even
      # one whose grant was revoked. That makes each authorization code
      # single-use, so it must hold when two requests race. Using code_id as
      # the grant's id, in a unique column, is the simplest way.
      def create_grant(code_id:, authorization_request:, approved_by:)
        raise NotImplementedError, "#{self.class.name} must define create_grant"
      end

      # Returns the grant, which must respond to id, client_id, resource and
      # scope, and to each attribute in approved_by. Returns nil if there is no
      # grant, or it was revoked.
      def find_grant(id)
        raise NotImplementedError, "#{self.class.name} must define find_grant"
      end

      # Revokes a grant and every token under it. Its id stays taken.
      def revoke_grant(id)
        raise NotImplementedError, "#{self.class.name} must define revoke_grant"
      end

      # Returns the token string for a hash of claims.
      def issue_token(claims)
        raise NotImplementedError, "#{self.class.name} must define issue_token"
      end

      # Issues an access token and a refresh token together, after an
      # authorization code or a refresh token is exchanged, and returns the
      # two strings. Optional: by default it calls issue_token for each. A
      # subclass can override it to store the pair together, or to note the
      # newest refresh token on the grant.
      def issue_tokens(access, refresh)
        [issue_token(access), issue_token(refresh)]
      end

      # Returns the claims hash for a token string. Returns nil if issue_token
      # didn't issue the token, or if the token was revoked. The caller checks
      # expiry.
      #
      # A refresh token that consume_refresh_token has used must still read,
      # so the gem can tell when it's used again, and revoke the grant.
      def read_token(token)
        raise NotImplementedError, "#{self.class.name} must define read_token"
      end

      # Marks a refresh token as used. Takes the claims hash from read_token.
      # Returns true the first time and false after that, even when two
      # requests race. The gem treats false as a copied token and revokes the
      # grant.
      def consume_refresh_token(claims)
        raise NotImplementedError, "#{self.class.name} must define consume_refresh_token"
      end

      # Revokes one token. Encrypted tokens can't be revoked one at a time, so
      # by default this revokes the token's grant.
      def revoke_token(claims)
        revoke_grant(claims[:grant_id])
      end
    end
  end
end
