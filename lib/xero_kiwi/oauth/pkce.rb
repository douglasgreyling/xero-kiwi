# frozen_string_literal: true

require "base64"
require "digest"
require "securerandom"

module XeroKiwi
  class OAuth
    # Implementation of PKCE (Proof Key for Code Exchange — RFC 7636).
    #
    # PKCE binds the auth code to the original authorisation request: the
    # client generates a random verifier, hashes it into a challenge, sends
    # the challenge with the authorise call, then proves possession of the
    # original verifier when exchanging the code. An attacker that intercepts
    # the auth code can't redeem it without the verifier.
    #
    # Required for public OAuth clients (mobile, SPA), recommended for
    # confidential server-side clients as defence in depth.
    class PKCE
      CHALLENGE_METHOD = "S256"

      attr_reader :verifier, :challenge

      def self.generate
        new(verifier: SecureRandom.urlsafe_base64(32))
      end

      def initialize(verifier:)
        @verifier  = verifier
        @challenge = compute_challenge(verifier)
      end

      def to_h
        {
          code_verifier:         verifier,
          code_challenge:        challenge,
          code_challenge_method: CHALLENGE_METHOD
        }
      end

      private

      # Per RFC 7636 §4.2: BASE64URL-ENCODE(SHA256(ASCII(verifier))) with
      # padding stripped.
      def compute_challenge(verifier)
        digest = Digest::SHA256.digest(verifier)
        Base64.urlsafe_encode64(digest, padding: false)
      end
    end
  end
end
