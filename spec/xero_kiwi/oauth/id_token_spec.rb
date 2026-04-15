# frozen_string_literal: true

RSpec.describe XeroKiwi::OAuth::IDToken do
  let(:client_id) { "client_xyz" }
  let(:jwks)      { -> { TestJWT::JWKS_KEYS } }

  describe ".verify" do
    context "with a valid token" do
      it "returns an IDToken with parsed claims" do
        token = TestJWT.build_id_token(aud: client_id)

        verified = described_class.verify(token, client_id: client_id, jwks: jwks)

        expect(verified).to be_a(described_class).and have_attributes(
          subject:     "user_sub_123",
          email:       "user@example.com",
          given_name:  "Jane",
          family_name: "Doe"
        )
        expect(verified.expires_at).to be_a(Time).and(have_attributes(utc_offset: 0))
      end

      it "exposes the full claims hash" do
        token    = TestJWT.build_id_token(aud: client_id, custom: "value")
        verified = described_class.verify(token, client_id: client_id, jwks: jwks)

        expect(verified.claims).to include("sub" => "user_sub_123", "custom" => "value")
      end
    end

    context "when validation fails" do
      it "raises IDTokenError on an expired token" do
        token = TestJWT.build_id_token(aud: client_id, exp: (Time.now - 60).to_i)

        expect { described_class.verify(token, client_id: client_id, jwks: jwks) }
          .to raise_error(XeroKiwi::OAuth::IDTokenError)
      end

      it "raises IDTokenError when the audience is wrong" do
        token = TestJWT.build_id_token(aud: "different_client")

        expect { described_class.verify(token, client_id: client_id, jwks: jwks) }
          .to raise_error(XeroKiwi::OAuth::IDTokenError)
      end

      it "raises IDTokenError when the issuer is wrong" do
        token = TestJWT.build_id_token(aud: client_id, iss: "https://evil.example.com")

        expect { described_class.verify(token, client_id: client_id, jwks: jwks) }
          .to raise_error(XeroKiwi::OAuth::IDTokenError)
      end

      it "raises IDTokenError when the signature was made with a different key" do
        attacker_key = OpenSSL::PKey::RSA.generate(2048)
        token        = TestJWT.build_id_token(key: attacker_key, aud: client_id)

        expect { described_class.verify(token, client_id: client_id, jwks: jwks) }
          .to raise_error(XeroKiwi::OAuth::IDTokenError)
      end

      it "raises IDTokenError when the kid does not match any JWKS entry" do
        token = TestJWT.build_id_token(kid: "unknown-kid", aud: client_id)

        expect { described_class.verify(token, client_id: client_id, jwks: jwks) }
          .to raise_error(XeroKiwi::OAuth::IDTokenError)
      end
    end

    context "when verifying nonce" do
      it "passes when the nonce in the token matches the expected value" do
        token = TestJWT.build_id_token(aud: client_id, nonce: "expected_nonce")

        verified = described_class.verify(token, client_id: client_id, nonce: "expected_nonce", jwks: jwks)

        expect(verified.nonce).to eq("expected_nonce")
      end

      it "raises when the nonce in the token does not match" do
        token = TestJWT.build_id_token(aud: client_id, nonce: "wrong_nonce")

        expect { described_class.verify(token, client_id: client_id, nonce: "expected_nonce", jwks: jwks) }
          .to raise_error(XeroKiwi::OAuth::IDTokenError, /nonce mismatch/)
      end

      it "raises when nonce is expected but missing from the token" do
        token = TestJWT.build_id_token(aud: client_id)

        expect { described_class.verify(token, client_id: client_id, nonce: "expected_nonce", jwks: jwks) }
          .to raise_error(XeroKiwi::OAuth::IDTokenError, /nonce mismatch/)
      end
    end

    context "with bad inputs" do
      it "raises ArgumentError when id_token is blank" do
        expect { described_class.verify(nil, client_id: client_id) }.to raise_error(ArgumentError)
        expect { described_class.verify("",  client_id: client_id) }.to raise_error(ArgumentError)
      end

      it "raises ArgumentError when client_id is blank" do
        expect { described_class.verify("token", client_id: nil) }.to raise_error(ArgumentError)
        expect { described_class.verify("token", client_id: "") }.to  raise_error(ArgumentError)
      end
    end
  end
end
