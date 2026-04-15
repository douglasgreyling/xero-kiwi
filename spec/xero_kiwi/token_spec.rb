# frozen_string_literal: true

RSpec.describe XeroKiwi::Token do
  let(:now) { Time.utc(2026, 4, 9, 12, 0, 0) }

  describe "#expired?" do
    it "is false when expires_at is in the future" do
      token = described_class.new(access_token: "x", expires_at: now + 60)
      expect(token.expired?(now: now)).to be false
    end

    it "is true when expires_at is exactly now or in the past" do
      expect(described_class.new(access_token: "x", expires_at: now).expired?(now: now)).to        be true
      expect(described_class.new(access_token: "x", expires_at: now - 1).expired?(now: now)).to be true
    end

    it "is false when expires_at is unknown (nil)" do
      expect(described_class.new(access_token: "x").expired?).to be false
    end
  end

  describe "#expiring_soon?" do
    it "is true when expires_at falls inside the window" do
      token = described_class.new(access_token: "x", expires_at: now + 30)
      expect(token.expiring_soon?(within: 60, now: now)).to be true
    end

    it "is false when expires_at is outside the window" do
      token = described_class.new(access_token: "x", expires_at: now + 120)
      expect(token.expiring_soon?(within: 60, now: now)).to be false
    end

    it "respects a custom window" do
      token = described_class.new(access_token: "x", expires_at: now + 600)
      expect(token.expiring_soon?(within: 1200, now: now)).to be true
      expect(token.expiring_soon?(within: 60,   now: now)).to be false
    end

    it "is false when expires_at is unknown" do
      expect(described_class.new(access_token: "x").expiring_soon?).to be false
    end
  end

  describe "#valid?" do
    it "is true when the token is non-empty and not expired" do
      token = described_class.new(access_token: "x", expires_at: now + 60)
      expect(token.valid?(now: now)).to be true
    end

    it "is false when the token is expired" do
      token = described_class.new(access_token: "x", expires_at: now - 1)
      expect(token.valid?(now: now)).to be false
    end

    it "is false when access_token is empty" do
      expect(described_class.new(access_token: "").valid?).to be false
    end
  end

  describe "#refreshable?" do
    it "is true when a refresh_token is present" do
      token = described_class.new(access_token: "x", refresh_token: "y")
      expect(token).to be_refreshable
    end

    it "is false when refresh_token is missing or empty" do
      expect(described_class.new(access_token: "x")).not_to be_refreshable
      expect(described_class.new(access_token: "x", refresh_token: "")).not_to be_refreshable
    end
  end

  describe ".from_oauth_response" do
    let(:requested_at) { now }
    let(:payload) do
      {
        "access_token"  => "ya29.access",
        "refresh_token" => "1//refresh",
        "expires_in"    => 1800,
        "token_type"    => "Bearer",
        "scope"         => "offline_access accounting.transactions",
        "id_token"      => "eyJhbG..."
      }
    end

    it "computes expires_at from requested_at + expires_in" do
      token = described_class.from_oauth_response(payload, requested_at: requested_at)
      expect(token.expires_at).to eq(requested_at + 1800)
    end

    it "extracts the token fields" do
      token = described_class.from_oauth_response(payload, requested_at: requested_at)
      expect(token).to have_attributes(
        access_token:  "ya29.access",
        refresh_token: "1//refresh",
        token_type:    "Bearer",
        scope:         "offline_access accounting.transactions",
        id_token:      "eyJhbG..."
      )
    end

    it "tolerates missing expires_in (leaves expires_at nil)" do
      token = described_class.from_oauth_response(payload.except("expires_in"))
      expect(token.expires_at).to be_nil
    end

    it "accepts symbol-keyed payloads too" do
      token = described_class.from_oauth_response(payload.transform_keys(&:to_sym),
                                                  requested_at: requested_at)
      expect(token.access_token).to eq("ya29.access")
    end
  end

  describe "#inspect" do
    it "does not leak the access token" do
      token = described_class.new(access_token: "ya29.supersecret", refresh_token: "rt")
      expect(token.inspect).not_to include("ya29.supersecret")
      expect(token.inspect).to include("[FILTERED]")
    end
  end
end
