module StatelessMcp
  module OAuth
    # An OAuth error response, with an error code from the OAuth registry. At
    # the authorization endpoint, an error that isn't redirectable means the
    # client or its redirect_uri can't be trusted. The app shows that error to
    # the person, and doesn't redirect.
    class Error < StandardError
      attr_reader :code, :status

      def initialize(code, description = nil, status: 400, redirectable: true)
        super(description || code)
        @code = code
        @status = status
        @redirectable = redirectable
      end

      def redirectable?
        @redirectable
      end

      def to_h
        { error: code, error_description: message }
      end
    end
  end
end
