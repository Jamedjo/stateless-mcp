require "base64"
require "digest"
require "rack/utils"

module StatelessMcp
  module OAuth
    # Only the S256 method is supported. With the "plain" method, the code
    # challenge equals the code verifier, so anyone who saw the authorization
    # request would know the code verifier.
    module Pkce
      METHOD = "S256"
      # RFC 7636 section 4.1: 43 to 128 unreserved characters.
      VERIFIER = /\A[A-Za-z0-9\-._~]{43,128}\z/
      # A SHA-256 digest in unpadded base64url is always 43 characters.
      CHALLENGE = /\A[A-Za-z0-9\-_]{43}\z/

      def self.challenge?(challenge)
        challenge.is_a?(String) && CHALLENGE.match?(challenge)
      end

      def self.challenge_for(verifier)
        Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
      end

      # Compared in constant time, so the time taken says nothing about how
      # much of the challenge matched.
      def self.verified?(verifier, challenge)
        return false unless verifier.is_a?(String) && VERIFIER.match?(verifier) && challenge?(challenge)
        Rack::Utils.secure_compare(challenge_for(verifier), challenge)
      end
    end
  end
end
