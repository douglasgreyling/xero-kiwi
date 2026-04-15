# frozen_string_literal: true

require "base64"
require "uri"

RSpec.describe XeroKiwi::OAuth do
  let(:client_id)     { "client_xyz" }
  let(:client_secret) { "secret_abc" }
  let(:redirect_uri)  { "https://app.example.com/xero/callback" }
  let(:oauth) do
    described_class.new(
      client_id:     client_id,
      client_secret: client_secret,
      redirect_uri:  redirect_uri
    )
  end

  let(:json_headers)   { { "Content-Type" => "application/json" } }
  let(:token_endpoint) { "https://identity.xero.com/connect/token" }

  describe ".generate_state" do
    it "returns a URL-safe random token" do
      state = described_class.generate_state
      expect(state.length).to be >= 32
      expect(state).to match(/\A[A-Za-z0-9_-]+\z/)
    end

    it "returns a different value on each call" do
      expect(described_class.generate_state).not_to eq(described_class.generate_state)
    end
  end

  describe ".generate_pkce" do
    it "delegates to PKCE.generate" do
      expect(described_class.generate_pkce).to be_a(XeroKiwi::OAuth::PKCE)
    end
  end

  describe ".verify_state!" do
    it "is a no-op when received and expected match exactly" do
      expect { described_class.verify_state!(received: "abc123", expected: "abc123") }.not_to raise_error
    end

    it "raises StateMismatchError when values differ" do
      expect { described_class.verify_state!(received: "abc", expected: "xyz") }
        .to raise_error(XeroKiwi::OAuth::StateMismatchError)
    end

    it "raises when lengths differ (avoiding OpenSSL ArgumentError)" do
      expect { described_class.verify_state!(received: "abcd", expected: "abc") }
        .to raise_error(XeroKiwi::OAuth::StateMismatchError)
    end

    it "raises when received is nil" do
      expect { described_class.verify_state!(received: nil, expected: "abc") }
        .to raise_error(XeroKiwi::OAuth::StateMismatchError)
    end

    it "raises when expected is nil" do
      expect { described_class.verify_state!(received: "abc", expected: nil) }
        .to raise_error(XeroKiwi::OAuth::StateMismatchError)
    end
  end

  describe "#authorization_url" do
    let(:scopes) { %w[openid profile email accounting.transactions offline_access] }
    let(:state)  { "csrf_state_value" }

    def parse_query(url)
      URI.decode_www_form(URI(url).query).to_h
    end

    it "builds the URL against the Xero authorise endpoint" do
      url = oauth.authorization_url(scopes: scopes, state: state)
      expect(url).to start_with("https://login.xero.com/identity/connect/authorize?")
    end

    it "includes the standard OAuth params" do
      params = parse_query(oauth.authorization_url(scopes: scopes, state: state))

      expect(params).to include(
        "response_type" => "code",
        "client_id"     => client_id,
        "redirect_uri"  => redirect_uri,
        "scope"         => scopes.join(" "),
        "state"         => state
      )
    end

    it "omits PKCE params when no PKCE object is given" do
      params = parse_query(oauth.authorization_url(scopes: scopes, state: state))
      expect(params).not_to have_key("code_challenge")
      expect(params).not_to have_key("code_challenge_method")
    end

    it "includes PKCE params when a PKCE object is given" do
      pkce   = XeroKiwi::OAuth::PKCE.generate
      params = parse_query(oauth.authorization_url(scopes: scopes, state: state, pkce: pkce))

      expect(params["code_challenge"]).to        eq(pkce.challenge)
      expect(params["code_challenge_method"]).to eq("S256")
    end

    it "includes the nonce param when provided" do
      params = parse_query(oauth.authorization_url(scopes: scopes, state: state, nonce: "nonce_xyz"))
      expect(params["nonce"]).to eq("nonce_xyz")
    end

    it "raises when scopes is empty" do
      expect { oauth.authorization_url(scopes: [], state: state) }.to raise_error(ArgumentError)
    end

    it "raises when state is empty" do
      expect { oauth.authorization_url(scopes: scopes, state: "") }.to raise_error(ArgumentError)
    end
  end

  describe "#exchange_code" do
    let(:successful_response) do
      JSON.dump(
        "access_token"  => "new_access_token",
        "refresh_token" => "new_refresh_token",
        "expires_in"    => 1800,
        "token_type"    => "Bearer",
        "scope"         => "openid offline_access accounting.transactions",
        "id_token"      => "eyJhbG..."
      )
    end

    it "POSTs to the token endpoint with HTTP Basic auth, code, and redirect_uri" do
      expected_basic = "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}"
      stub           = stub_request(:post, token_endpoint)
                       .with(
                         headers: {
                           "Authorization" => expected_basic,
                           "Content-Type"  => "application/x-www-form-urlencoded"
                         },
                         body:    {
                           grant_type:   "authorization_code",
                           code:         "the_auth_code",
                           redirect_uri: redirect_uri
                         }
                       )
                       .to_return(status: 200, body: successful_response, headers: json_headers)

      oauth.exchange_code(code: "the_auth_code")

      expect(stub).to have_been_requested
    end

    it "returns a XeroKiwi::Token built from the response" do
      stub_request(:post, token_endpoint)
        .to_return(status: 200, body: successful_response, headers: json_headers)

      token = oauth.exchange_code(code: "the_auth_code")

      expect(token).to be_a(XeroKiwi::Token).and have_attributes(
        access_token:  "new_access_token",
        refresh_token: "new_refresh_token",
        id_token:      "eyJhbG..."
      )
    end

    it "includes code_verifier in the body when one is supplied" do
      stub = stub_request(:post, token_endpoint)
             .with(
               body: {
                 grant_type:    "authorization_code",
                 code:          "the_auth_code",
                 redirect_uri:  redirect_uri,
                 code_verifier: "my_verifier_xyz"
               }
             )
             .to_return(status: 200, body: successful_response, headers: json_headers)

      oauth.exchange_code(code: "the_auth_code", code_verifier: "my_verifier_xyz")

      expect(stub).to have_been_requested
    end

    it "raises CodeExchangeError on invalid_grant" do
      stub_request(:post, token_endpoint)
        .to_return(status: 400, body: JSON.dump("error" => "invalid_grant"), headers: json_headers)

      expect { oauth.exchange_code(code: "bad_code") }.to raise_error(XeroKiwi::OAuth::CodeExchangeError)
    end

    it "raises ArgumentError when code is blank" do
      expect { oauth.exchange_code(code: nil) }.to raise_error(ArgumentError)
      expect { oauth.exchange_code(code: "") }.to  raise_error(ArgumentError)
    end
  end

  describe "#revoke_token" do
    let(:revoke_endpoint) { "https://identity.xero.com/connect/revocation" }

    it "POSTs to the revocation endpoint with HTTP Basic auth and the refresh token" do
      expected_basic = "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}"
      stub           = stub_request(:post, revoke_endpoint)
                       .with(
                         headers: {
                           "Authorization" => expected_basic,
                           "Content-Type"  => "application/x-www-form-urlencoded"
                         },
                         body:    { token: "rt_to_revoke", token_type_hint: "refresh_token" }
                       )
                       .to_return(status: 200, body: "")

      expect(oauth.revoke_token(refresh_token: "rt_to_revoke")).to be true
      expect(stub).to have_been_requested
    end

    it "raises AuthenticationError when client credentials are wrong" do
      stub_request(:post, revoke_endpoint)
        .to_return(status: 401, body: JSON.dump("error" => "invalid_client"), headers: json_headers)

      expect { oauth.revoke_token(refresh_token: "rt") }.to raise_error(XeroKiwi::AuthenticationError)
    end

    it "raises ArgumentError when refresh_token is blank" do
      expect { oauth.revoke_token(refresh_token: nil) }.to raise_error(ArgumentError)
      expect { oauth.revoke_token(refresh_token: "") }.to  raise_error(ArgumentError)
    end

    it "works on an OAuth instance constructed without a redirect_uri" do
      stub_request(:post, revoke_endpoint).to_return(status: 200, body: "")

      revoker_only = described_class.new(client_id: client_id, client_secret: client_secret)
      expect(revoker_only.revoke_token(refresh_token: "rt")).to be true
    end
  end

  describe "redirect_uri requirement" do
    it "is enforced at authorization_url time, not construction time" do
      revoker_only = described_class.new(client_id: client_id, client_secret: client_secret)

      expect { revoker_only.authorization_url(scopes: %w[openid], state: "abc") }
        .to raise_error(ArgumentError, /redirect_uri/)
    end

    it "is enforced at exchange_code time, not construction time" do
      revoker_only = described_class.new(client_id: client_id, client_secret: client_secret)

      expect { revoker_only.exchange_code(code: "abc") }
        .to raise_error(ArgumentError, /redirect_uri/)
    end
  end

  describe "#verify_id_token" do
    let(:client_id) { "client_xyz" } # must match TestJWT default audience
    let(:jwks_endpoint) do
      "https://identity.xero.com/.well-known/openid-configuration/jwks"
    end

    it "fetches JWKS from Xero and verifies the token" do
      stub_request(:get, jwks_endpoint)
        .to_return(status: 200, body: TestJWT::JWKS_BODY, headers: json_headers)

      token    = TestJWT.build_id_token(aud: client_id)
      verified = oauth.verify_id_token(token)

      expect(verified.subject).to eq("user_sub_123")
      expect(verified.email).to   eq("user@example.com")
    end

    it "caches the JWKS so repeated verifications only fetch once" do
      stub = stub_request(:get, jwks_endpoint)
             .to_return(status: 200, body: TestJWT::JWKS_BODY, headers: json_headers)

      token = TestJWT.build_id_token(aud: client_id)

      3.times { oauth.verify_id_token(token) }

      expect(stub).to have_been_requested.once
    end

    it "passes the nonce through to IDToken.verify" do
      stub_request(:get, jwks_endpoint)
        .to_return(status: 200, body: TestJWT::JWKS_BODY, headers: json_headers)

      token = TestJWT.build_id_token(aud: client_id, nonce: "abc123")

      expect(oauth.verify_id_token(token, nonce: "abc123").nonce).to eq("abc123")
      expect { oauth.verify_id_token(token, nonce: "wrong") }
        .to raise_error(XeroKiwi::OAuth::IDTokenError)
    end
  end
end
