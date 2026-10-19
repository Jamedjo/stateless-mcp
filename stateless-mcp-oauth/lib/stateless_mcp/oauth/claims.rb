require "json"

module StatelessMcp
  module OAuth
    # A claim is one fact about a token, such as which grant it belongs to or
    # when it expires. Claims are all of them for one authorization code,
    # access token or refresh token.
    #
    # - kind: "code", "access" or "refresh".
    # - id: a random id for the token.
    # - grant_id: a grant is one person's approval of one client, so revoking
    #   it revokes every token that came from it. An authorization code has
    #   none, as exchanging it creates the grant.
    # - expires_at: seconds since the epoch.
    # - authorization_request: for an authorization code only, what the
    #   client asked for and the person approved. That's client_id,
    #   redirect_uri, code_challenge, scope and resource.
    # - approved_by: for an authorization code only, the app's attributes for
    #   who approved, such as { user_id: 42 }.
    Claims = Data.define(:kind, :id, :grant_id, :expires_at, :authorization_request, :approved_by)

    class Claims
      KINDS = %i[code access refresh].freeze
      AUTHORIZATION_REQUEST = %i[client_id redirect_uri code_challenge scope resource].freeze

      def initialize(kind:, id:, expires_at:, grant_id: nil, authorization_request: nil, approved_by: nil)
        kind = kind.to_sym if kind.is_a?(String)
        raise ArgumentError, "kind must be one of #{KINDS.join(", ")}; got #{kind.inspect}" unless KINDS.include?(kind)
        raise ArgumentError, "id must be a String" unless id.is_a?(String)
        raise ArgumentError, "grant_id must be a String, and nil for an authorization code" unless kind == :code ? grant_id.nil? : grant_id.is_a?(String)
        raise ArgumentError, "expires_at must be an Integer" unless expires_at.is_a?(Integer)
        code = kind == :code
        raise ArgumentError, "authorization_request is required for an authorization code and not allowed for other kinds" unless code == authorization_request.is_a?(Hash)
        raise ArgumentError, "approved_by is required for an authorization code and not allowed for other kinds" unless code == approved_by.is_a?(Hash)
        authorization_request = self.class.symbolize(authorization_request).slice(*AUTHORIZATION_REQUEST).freeze if code
        approved_by = self.class.symbolize(approved_by).freeze if code
        super
      end

      # Builds Claims from a hash shaped like to_h's output. Ignores keys the
      # storage added. Returns nil if the hash isn't valid claims.
      def self.from_h(hash)
        hash = symbolize(hash) or return nil
        new(**members.to_h { |member| [member, hash[member]] })
      rescue ArgumentError, NoMethodError
        nil
      end

      # Deep-symbolizes a hash's keys, since JSON returns string keys. Returns
      # nil for anything that isn't a hash.
      def self.symbolize(hash)
        JSON.parse(JSON.generate(hash), symbolize_names: true) if hash.is_a?(Hash)
      end

      # A hash with symbol keys and kind as a string, so it serializes to JSON.
      def to_h
        super.merge(kind: kind.to_s).compact
      end

      def expired?(now = Time.now)
        expires_at <= now.to_i
      end
    end
  end
end
