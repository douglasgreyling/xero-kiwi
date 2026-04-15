# frozen_string_literal: true

require "base64"

RSpec.describe XeroKiwi::TokenRefresher do
  let(:client_id)     { "client123" }
  let(:client_secret) { "secret456" }
  let(:refresher)     { described_class.new(client_id: client_id, client_secret: client_secret) }
  let(:token_endpoint) { "https://identity.xero.com/connect/token" }
  let(:json_headers)   { { "Content-Type" => "application/json" } }

  let(:successful_response) do
    {
      "access_token"  => "new_access_token",
      "refresh_token" => "new_refresh_token",
      "expires_in"    => 1800,
      "token_type"    => "Bearer",
      "scope"         => "offline_access accounting.transactions",
      "id_token"      => "eyJhbG..."
    }
  end

  describe "#refresh" do
    it "POSTs to the Xero identity endpoint with HTTP Basic auth and form body" do
      expected_basic = "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}"
      stub           = stub_request(:post, token_endpoint)
                       .with(
                         headers: {
                           "Authorization" => expected_basic,
                           "Content-Type"  => "application/x-www-form-urlencoded",
                           "Accept"        => "application/json"
                         },
                         body:    { grant_type: "refresh_token", refresh_token: "old_refresh" }
                       )
                       .to_return(status: 200, body: JSON.dump(successful_response), headers: json_headers)

      refresher.refresh(refresh_token: "old_refresh")

      expect(stub).to have_been_requested
    end

    it "returns a XeroKiwi::Token built from the response" do
      stub_request(:post, token_endpoint)
        .to_return(status: 200, body: JSON.dump(successful_response), headers: json_headers)

      token = refresher.refresh(refresh_token: "old_refresh")

      expect(token).to be_a(XeroKiwi::Token).and have_attributes(
        access_token:  "new_access_token",
        refresh_token: "new_refresh_token",
        token_type:    "Bearer",
        scope:         "offline_access accounting.transactions"
      )
      expect(token.expires_at).to be > Time.now
    end

    it "raises TokenRefreshError on invalid_grant (refresh token expired/rotated)" do
      stub_request(:post, token_endpoint)
        .to_return(
          status:  400,
          body:    JSON.dump("error" => "invalid_grant"),
          headers: json_headers
        )

      expect { refresher.refresh(refresh_token: "expired_refresh") }
        .to raise_error(XeroKiwi::TokenRefreshError) { |e| expect(e.status).to eq(400) }
    end

    it "raises TokenRefreshError on 401 invalid_client" do
      stub_request(:post, token_endpoint)
        .to_return(
          status:  401,
          body:    JSON.dump("error" => "invalid_client"),
          headers: json_headers
        )

      expect { refresher.refresh(refresh_token: "rt") }.to raise_error(XeroKiwi::TokenRefreshError)
    end

    it "raises ArgumentError when refresh_token is blank" do
      expect { refresher.refresh(refresh_token: nil) }.to raise_error(ArgumentError)
      expect { refresher.refresh(refresh_token: "") }.to  raise_error(ArgumentError)
    end
  end
end
