# frozen_string_literal: true

require "jwt"
require "openssl"

# Test fixtures for JWT/JWKS verification specs. Generating an RSA keypair
# costs ~100ms; we do it once at file-load time and reuse it across every
# example.
module TestJWT
  PRIVATE_KEY = OpenSSL::PKey::RSA.generate(2048)
  KID         = "test-kid-1"
  ISSUER      = "https://identity.xero.com"
  JWKS_KEYS   = [JWT::JWK.new(PRIVATE_KEY, kid: KID).export].freeze
  JWKS_BODY   = JSON.dump(keys: JWKS_KEYS).freeze

  # Builds a signed JWT with sensible defaults that callers can override per
  # example. Uses **claims so call sites can write
  # `TestJWT.build_id_token(aud: "x", nonce: "y")` directly.
  def self.build_id_token(key: PRIVATE_KEY, kid: KID, **claims)
    payload = {
      iss:         ISSUER,
      aud:         "client_xyz",
      sub:         "user_sub_123",
      email:       "user@example.com",
      given_name:  "Jane",
      family_name: "Doe",
      exp:         (Time.now + 600).to_i,
      iat:         Time.now.to_i
    }.merge(claims)

    JWT.encode(payload, key, "RS256", { kid: kid })
  end
end
