# frozen_string_literal: true

require "json"
require "jwt"
require "net/http"
require "openssl"
require "uri"

module XeroKiwi
  class OAuth
    # Verifies an OIDC id_token (JWT) returned by Xero. Validates the
    # signature against Xero's JWKS and checks the standard OIDC claims
    # (iss, aud, exp). Optionally verifies the nonce claim if you sent one
    # in the authorisation request.
    #
    # Two ways to use this:
    #
    #   # 1. Via an OAuth instance — uses the instance's JWKS cache, so
    #   #    repeated verifications don't refetch Xero's signing keys.
    #   verified = oauth.verify_id_token(token.id_token)
    #
    #   # 2. Standalone class method — fetches JWKS fresh on each call.
    #   #    Fine for one-off verification.
    #   verified = XeroKiwi::OAuth::IDToken.verify(id_token, client_id: "abc123")
    #
    #   verified.subject       # OIDC `sub` claim
    #   verified.email         # if `email` scope was granted
    #   verified.given_name    # if `profile` scope was granted
    #   verified.expires_at    # Time
    #   verified.claims        # full claims hash
    class IDToken
      ISSUER     = "https://identity.xero.com"
      ALGORITHMS = %w[RS256].freeze

      attr_reader :claims

      def self.verify(id_token, client_id:, nonce: nil, jwks: nil)
        raise ArgumentError, "id_token is required"  if id_token.nil?  || id_token.empty?
        raise ArgumentError, "client_id is required" if client_id.nil? || client_id.empty?

        decoded = decode(id_token, client_id, jwks)
        claims  = decoded.first
        verify_nonce!(claims, nonce) if nonce
        new(claims)
      rescue JWT::DecodeError => e
        raise IDTokenError, "ID token verification failed: #{e.message}"
      end

      def self.decode(id_token, client_id, jwks)
        jwks_proc = jwks || method(:fetch_jwks_directly)
        JWT.decode(
          id_token,
          nil,
          true,
          algorithms: ALGORITHMS,
          iss:        ISSUER,
          verify_iss: true,
          aud:        client_id,
          verify_aud: true,
          jwks:       ->(_options) { { keys: jwks_proc.call } }
        )
      end
      private_class_method :decode

      # Fallback JWKS fetcher used by the class method when no fetcher is
      # injected. Net::HTTP keeps this dependency-free at the call site;
      # OAuth#verify_id_token uses an instance-cached Faraday fetcher
      # instead.
      def self.fetch_jwks_directly
        body = Net::HTTP.get(URI(Identity::JWKS_URL))
        JSON.parse(body).fetch("keys")
      rescue StandardError => e
        raise IDTokenError, "failed to fetch JWKS: #{e.message}"
      end
      private_class_method :fetch_jwks_directly

      # ruby-jwt's `iss`/`aud`/`exp` validation runs in JWT.decode itself —
      # we only need to handle `nonce` here, since it's not a standard JWT
      # claim and not part of ruby-jwt's built-in validators.
      def self.verify_nonce!(claims, expected)
        actual = claims["nonce"].to_s
        return if !expected.empty? && actual.bytesize == expected.bytesize &&
                  OpenSSL.fixed_length_secure_compare(actual, expected)

        raise IDTokenError, "ID token nonce mismatch"
      end
      private_class_method :verify_nonce!

      def initialize(claims)
        @claims = claims
      end

      def subject     = claims["sub"]
      def email       = claims["email"]
      def given_name  = claims["given_name"]
      def family_name = claims["family_name"]
      def nonce       = claims["nonce"]
      def issued_at   = claims["iat"] && Time.at(claims["iat"]).utc
      def expires_at  = claims["exp"] && Time.at(claims["exp"]).utc
    end
  end
end
