module StatelessMcp
  module OAuth
    # Raised by ProtectedResource#verified_grant! for a token it refuses. The
    # reason is for the app's logs and metrics, never for the client, so every
    # refused token gets the same 401.
    class InvalidToken < StandardError
      REASONS = %i[missing unknown not_an_access_token expired revoked other_mcp_server].freeze

      attr_reader :reason

      def initialize(reason)
        raise ArgumentError, "reason must be one of #{REASONS.join(", ")}; got #{reason.inspect}" unless REASONS.include?(reason)
        @reason = reason
        super("The access token was refused: #{reason}")
      end
    end
  end
end
