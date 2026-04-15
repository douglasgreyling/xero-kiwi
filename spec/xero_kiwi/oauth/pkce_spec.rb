# frozen_string_literal: true

require "base64"
require "digest"

RSpec.describe XeroKiwi::OAuth::PKCE do
  describe ".generate" do
    it "produces a verifier of at least 43 URL-safe characters" do
      pkce = described_class.generate
      expect(pkce.verifier.length).to be >= 43
      expect(pkce.verifier).to match(/\A[A-Za-z0-9_-]+\z/)
    end

    it "produces a different verifier on each call" do
      expect(described_class.generate.verifier).not_to eq(described_class.generate.verifier)
    end

    it "computes the challenge as base64url(sha256(verifier)) with no padding" do
      pkce               = described_class.generate
      expected_digest    = Digest::SHA256.digest(pkce.verifier)
      expected_challenge = Base64.urlsafe_encode64(expected_digest, padding: false)
      expect(pkce.challenge).to eq(expected_challenge)
      expect(pkce.challenge).not_to include("=")
    end
  end

  describe "#to_h" do
    it "returns the form params Xero expects on the authorise + exchange calls" do
      pkce = described_class.new(verifier: "test_verifier_with_enough_chars_to_be_valid")
      expect(pkce.to_h).to eq(
        code_verifier:         "test_verifier_with_enough_chars_to_be_valid",
        code_challenge:        pkce.challenge,
        code_challenge_method: "S256"
      )
    end
  end
end
