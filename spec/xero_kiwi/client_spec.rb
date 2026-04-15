# frozen_string_literal: true

RSpec.describe XeroKiwi::Client do
  # Real token only needed at record time. On replay VCR substitutes the
  # filtered placeholder, so any non-empty string works for stubbed examples.
  let(:access_token) { ENV.fetch("XERO_ACCESS_TOKEN", "test_token") }

  # Tight retry settings keep the rate-limit specs deterministic and fast.
  let(:client) do
    described_class.new(
      access_token:  access_token,
      retry_options: { interval: 0, interval_randomness: 0, backoff_factor: 1, max: 2 }
    )
  end

  let(:json_headers)         { { "Content-Type" => "application/json" } }
  let(:connections_endpoint) { "https://api.xero.com/connections" }

  describe "#connections" do
    context "when talking to the live Xero API", vcr: { cassette_name: "connections/list" } do
      it "returns parsed XeroKiwi::Connection objects" do
        expect(client.connections).to all(be_a(XeroKiwi::Connection))
      end

      # The recorded cassette contains exactly one tenant. If you re-record
      # against an account with no connections, this expectation will fail —
      # which is the correct signal to also re-record against a real one.
      it "decodes Xero's connection schema correctly" do
        expect(client.connections.first).to have_attributes(
          id:               match(/\A[\w-]+\z/),
          tenant_id:        match(/\A[\w-]+\z/),
          tenant_type:      match(/\A(?:ORGANISATION|PRACTICE)\z/),
          tenant_name:      a_kind_of(String).and(satisfy { |s| !s.empty? }),
          created_date_utc: a_kind_of(Time).and(have_attributes(utc_offset: 0))
        )
      end
    end

    context "with stubbed responses" do
      let(:stubbed_payload) do
        [
          {
            "id"             => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
            "authEventId"    => "d99ecdfe-391d-43d2-b834-17636ba90e8d",
            "tenantId"       => "70784a63-d24b-46a9-a4db-0e70a274b056",
            "tenantType"     => "ORGANISATION",
            "tenantName"     => "Maple Florists Ltd",
            "createdDateUtc" => "2019-07-09T23:40:30.1833130",
            "updatedDateUtc" => "2020-05-15T01:35:13.8491980"
          }
        ]
      end

      it "sends the bearer token and accept header" do
        stub = stub_request(:get, connections_endpoint)
               .with(
                 headers: {
                   "Authorization" => "Bearer #{access_token}",
                   "Accept"        => "application/json"
                 }
               )
               .to_return(status: 200, body: JSON.dump(stubbed_payload), headers: json_headers)

        client.connections

        expect(stub).to have_been_requested
      end

      it "returns an empty array when no tenants are connected" do
        stub_request(:get, connections_endpoint)
          .to_return(status: 200, body: "[]", headers: json_headers)

        expect(client.connections).to eq([])
      end

      context "when the response is 401" do
        it "raises AuthenticationError carrying the status" do
          stub_request(:get, connections_endpoint)
            .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

          expect { client.connections }.to raise_error(XeroKiwi::AuthenticationError) do |error|
            expect(error.status).to eq(401)
          end
        end
      end

      context "when rate-limited (429)" do
        it "retries and returns the eventual success" do
          stub_request(:get, connections_endpoint)
            .to_return(
              { status: 429, headers: { "Retry-After" => "0" } },
              { status: 200, body: JSON.dump(stubbed_payload), headers: json_headers }
            )

          expect(client.connections.first.tenant_id).to eq("70784a63-d24b-46a9-a4db-0e70a274b056")
          expect(WebMock).to have_requested(:get, connections_endpoint).twice
        end

        it "raises RateLimitError once retries are exhausted, exposing problem + retry_after" do
          stub_request(:get, connections_endpoint)
            .to_return(
              status:  429,
              body:    "{}",
              headers: {
                "Retry-After"          => "0",
                "X-Rate-Limit-Problem" => "minute",
                "Content-Type"         => "application/json"
              }
            )

          expect { client.connections }.to raise_error(XeroKiwi::RateLimitError) do |error|
            expect(error.status).to eq(429)
            expect(error.problem).to eq("minute")
            expect(error.retry_after).to eq(0.0)
          end
        end
      end

      context "when 503 is returned" do
        it "retries on transient server errors" do
          stub_request(:get, connections_endpoint)
            .to_return(
              { status: 503, body: "{}", headers: json_headers },
              { status: 200, body: "[]", headers: json_headers }
            )

          expect(client.connections).to eq([])
          expect(WebMock).to have_requested(:get, connections_endpoint).twice
        end
      end

      context "when 500 is returned" do
        it "raises ServerError without retrying (500 is not in the retry list)" do
          stub_request(:get, connections_endpoint)
            .to_return(status: 500, body: "{}", headers: json_headers)

          expect { client.connections }.to raise_error(XeroKiwi::ServerError) do |error|
            expect(error.status).to eq(500)
          end
          expect(WebMock).to have_requested(:get, connections_endpoint).once
        end
      end
    end
  end

  describe "throttling" do
    let(:tenant_id)             { "70784a63-d24b-46a9-a4db-0e70a274b056" }
    let(:organisation_endpoint) { "https://api.xero.com/api.xro/2.0/Organisation" }
    let(:limiter)               { instance_double(XeroKiwi::Throttle::NullLimiter, acquire: nil) }

    let(:throttled_client) do
      described_class.new(
        access_token:  access_token,
        throttle:      limiter,
        retry_options: { interval: 0, interval_randomness: 0, backoff_factor: 1, max: 2 }
      )
    end

    it "calls the limiter once per request using the tenant id" do
      stub_request(:get, organisation_endpoint)
        .to_return(status: 200, body: '{"Organisations":[]}', headers: json_headers)

      throttled_client.organisation(tenant_id)

      expect(limiter).to have_received(:acquire).with(tenant_id).once
    end

    it "does not call the limiter for untenanted requests (e.g. /connections)" do
      stub_request(:get, connections_endpoint)
        .to_return(status: 200, body: "[]", headers: json_headers)

      throttled_client.connections

      expect(limiter).not_to have_received(:acquire)
    end

    it "re-enters the limiter on retries (429 then success consumes two tokens)" do
      stub_request(:get, organisation_endpoint)
        .to_return(
          { status: 429, headers: { "Retry-After" => "0", "Content-Type" => "application/json" }, body: "{}" },
          { status: 200, body: '{"Organisations":[]}', headers: json_headers }
        )

      throttled_client.organisation(tenant_id)

      expect(limiter).to have_received(:acquire).with(tenant_id).twice
    end

    it "propagates DailyLimitExhausted from the limiter without making a request" do
      allow(limiter).to receive(:acquire).and_raise(
        XeroKiwi::Throttle::DailyLimitExhausted.new(retry_after: 3600)
      )
      stub = stub_request(:get, organisation_endpoint)

      expect { throttled_client.organisation(tenant_id) }
        .to raise_error(XeroKiwi::Throttle::DailyLimitExhausted) { |e| expect(e.retry_after).to eq(3600) }

      expect(stub).not_to have_been_requested
    end
  end

  describe "#organisation" do
    let(:tenant_id)              { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:organisation_endpoint)  { "https://api.xero.com/api.xro/2.0/Organisation" }

    let(:organisation_payload) do
      {
        "Organisations" => [
          {
            "OrganisationID"   => "b2c885a0-e8de-4867-8b68-1442f7e4e162",
            "Name"             => "Maple Florists Ltd",
            "LegalName"        => "Maple Florists Limited",
            "OrganisationType" => "COMPANY",
            "BaseCurrency"     => "NZD",
            "CountryCode"      => "NZ",
            "IsDemoCompany"    => false,
            "CreatedDateUTC"   => "2019-07-09T23:40:30.1833130"
          }
        ]
      }
    end

    context "when talking to the live Xero API", vcr: { cassette_name: "organisation/get" } do
      it "returns a parsed XeroKiwi::Accounting::Organisation" do
        expect(client.organisation(tenant_id)).to be_a(XeroKiwi::Accounting::Organisation)
      end

      it "decodes Xero's organisation schema correctly" do
        expect(client.organisation(tenant_id)).to have_attributes(
          organisation_id:   match(/\A[\w-]+\z/),
          name:              a_kind_of(String).and(satisfy { |s| !s.empty? }),
          organisation_type: a_kind_of(String),
          base_currency:     match(/\A[A-Z]{3}\z/),
          country_code:      match(/\A[A-Z]{2}\z/),
          is_demo_company:   satisfy { |v| [true, false].include?(v) },
          created_date_utc:  a_kind_of(Time).and(have_attributes(utc_offset: 0))
        )
      end
    end

    it "sends the tenant-id header and returns a XeroKiwi::Accounting::Organisation" do
      stub = stub_request(:get, organisation_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(organisation_payload), headers: json_headers)

      org = client.organisation(tenant_id)

      expect(stub).to have_been_requested
      expect(org).to be_a(XeroKiwi::Accounting::Organisation)
      expect(org.name).to eq("Maple Florists Ltd")
      expect(org.organisation_id).to eq("b2c885a0-e8de-4867-8b68-1442f7e4e162")
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, organisation_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(organisation_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      org = client.organisation(connection)

      expect(org).to be_a(XeroKiwi::Accounting::Organisation)
      expect(org.name).to eq("Maple Florists Ltd")
    end

    it "raises ArgumentError when given nil" do
      expect { client.organisation(nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when given an empty string" do
      expect { client.organisation("") }.to raise_error(ArgumentError)
    end

    it "raises ClientError on 404" do
      stub_request(:get, organisation_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 404, body: '{"error":"not_found"}', headers: json_headers)

      expect { client.organisation(tenant_id) }.to raise_error(XeroKiwi::ClientError) do |error|
        expect(error.status).to eq(404)
      end
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, organisation_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.organisation(tenant_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#users" do
    let(:tenant_id)       { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:users_endpoint)  { "https://api.xero.com/api.xro/2.0/Users" }

    let(:users_payload) do
      {
        "Users" => [
          {
            "UserID"           => "7cf47fe2-c3dd-4c6b-9895-7ba767ba529c",
            "EmailAddress"     => "john.smith@mail.com",
            "FirstName"        => "John",
            "LastName"         => "Smith",
            "UpdatedDateUTC"   => "/Date(1516230549137+0000)/",
            "IsSubscriber"     => false,
            "OrganisationRole" => "ADMIN"
          }
        ]
      }
    end

    context "when talking to the live Xero API", vcr: { cassette_name: "users/list" } do
      it "returns parsed XeroKiwi::Accounting::User objects" do
        expect(client.users(tenant_id)).to all(be_a(XeroKiwi::Accounting::User))
      end

      it "decodes Xero's user schema correctly" do
        users = client.users(tenant_id)
        expect(users).not_to be_empty
        expect(users.first).to have_attributes(
          user_id:           match(/\A[\w-]+\z/),
          email_address:     a_kind_of(String).and(satisfy { |s| !s.empty? }),
          first_name:        a_kind_of(String),
          last_name:         a_kind_of(String),
          updated_date_utc:  a_kind_of(Time).and(have_attributes(utc_offset: 0)),
          is_subscriber:     satisfy { |v| [true, false].include?(v) },
          organisation_role: a_kind_of(String).and(satisfy { |s| !s.empty? })
        )
      end
    end

    it "sends the tenant-id header and returns XeroKiwi::Accounting::User objects" do
      stub = stub_request(:get, users_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(users_payload), headers: json_headers)

      users = client.users(tenant_id)

      expect(stub).to have_been_requested
      expect(users).to all(be_a(XeroKiwi::Accounting::User))
      expect(users.first.email_address).to eq("john.smith@mail.com")
      expect(users.first.user_id).to eq("7cf47fe2-c3dd-4c6b-9895-7ba767ba529c")
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, users_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(users_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      users = client.users(connection)

      expect(users).to all(be_a(XeroKiwi::Accounting::User))
    end

    it "returns an empty array when no users are present" do
      stub_request(:get, users_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump("Users" => []), headers: json_headers)

      expect(client.users(tenant_id)).to eq([])
    end

    it "raises ArgumentError when given nil" do
      expect { client.users(nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when given an empty string" do
      expect { client.users("") }.to raise_error(ArgumentError)
    end

    it "raises ClientError on 404" do
      stub_request(:get, users_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 404, body: '{"error":"not_found"}', headers: json_headers)

      expect { client.users(tenant_id) }.to raise_error(XeroKiwi::ClientError) do |error|
        expect(error.status).to eq(404)
      end
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, users_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.users(tenant_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#user" do
    let(:tenant_id)      { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:user_id)        { "7cf47fe2-c3dd-4c6b-9895-7ba767ba529c" }
    let(:user_endpoint)  { "https://api.xero.com/api.xro/2.0/Users/#{user_id}" }

    let(:user_payload) do
      {
        "Users" => [
          {
            "UserID"           => user_id,
            "EmailAddress"     => "john.smith@mail.com",
            "FirstName"        => "John",
            "LastName"         => "Smith",
            "UpdatedDateUTC"   => "/Date(1516230549137+0000)/",
            "IsSubscriber"     => false,
            "OrganisationRole" => "ADMIN"
          }
        ]
      }
    end

    it "sends the tenant-id header and returns a single XeroKiwi::Accounting::User" do
      stub = stub_request(:get, user_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(user_payload), headers: json_headers)

      user = client.user(tenant_id, user_id)

      expect(stub).to have_been_requested
      expect(user).to be_a(XeroKiwi::Accounting::User)
      expect(user.user_id).to eq(user_id)
      expect(user.email_address).to eq("john.smith@mail.com")
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, user_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(user_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      user = client.user(connection, user_id)

      expect(user).to be_a(XeroKiwi::Accounting::User)
    end

    it "raises ArgumentError when tenant_id is nil" do
      expect { client.user(nil, user_id) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when user_id is nil" do
      expect { client.user(tenant_id, nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when user_id is an empty string" do
      expect { client.user(tenant_id, "") }.to raise_error(ArgumentError)
    end

    it "raises ClientError on 404" do
      stub_request(:get, user_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 404, body: '{"error":"not_found"}', headers: json_headers)

      expect { client.user(tenant_id, user_id) }.to raise_error(XeroKiwi::ClientError) do |error|
        expect(error.status).to eq(404)
      end
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, user_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.user(tenant_id, user_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#contacts" do
    let(:tenant_id)             { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:contacts_api_endpoint) { "https://api.xero.com/api.xro/2.0/Contacts" }
    let(:contacts_payload) do
      {
        "Contacts" => [
          {
            "ContactID"       => "bd2270c3-8706-4c11-9cfb-000b551c3f51",
            "ContactStatus"   => "ACTIVE",
            "Name"            => "ABC Limited",
            "FirstName"       => "Andrea",
            "LastName"        => "Dutchess",
            "EmailAddress"    => "a.dutchess@abclimited.com",
            "IsSupplier"      => false,
            "IsCustomer"      => true,
            "DefaultCurrency" => "NZD",
            "UpdatedDateUTC"  => "/Date(1488391422280+0000)/",
            "Addresses"       => [{ "AddressType" => "POBOX" }],
            "Phones"          => [{ "PhoneType" => "DEFAULT" }]
          }
        ]
      }
    end

    context "when talking to the live Xero API", vcr: { cassette_name: "contacts/list" } do
      it "returns parsed XeroKiwi::Accounting::Contact objects" do
        expect(client.contacts(tenant_id)).to all(be_a(XeroKiwi::Accounting::Contact))
      end

      it "decodes Xero's contact schema correctly" do
        contacts = client.contacts(tenant_id)
        expect(contacts).not_to be_empty
        expect(contacts.first).to have_attributes(
          contact_id:       match(/\A[\w-]+\z/),
          name:             a_kind_of(String).and(satisfy { |s| !s.empty? }),
          contact_status:   a_kind_of(String),
          updated_date_utc: a_kind_of(Time).and(have_attributes(utc_offset: 0))
        )
      end
    end

    it "sends the tenant-id header and returns XeroKiwi::Accounting::Contact objects" do
      stub = stub_request(:get, contacts_api_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(contacts_payload), headers: json_headers)

      contacts = client.contacts(tenant_id)

      expect(stub).to have_been_requested
      expect(contacts).to all(be_a(XeroKiwi::Accounting::Contact))
      expect(contacts.first.name).to eq("ABC Limited")
      expect(contacts.first.contact_id).to eq("bd2270c3-8706-4c11-9cfb-000b551c3f51")
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, contacts_api_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(contacts_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      expect(client.contacts(connection)).to all(be_a(XeroKiwi::Accounting::Contact))
    end

    it "returns an empty array when no contacts are present" do
      stub_request(:get, contacts_api_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump("Contacts" => []), headers: json_headers)

      expect(client.contacts(tenant_id)).to eq([])
    end

    it "raises ArgumentError when given nil" do
      expect { client.contacts(nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when given an empty string" do
      expect { client.contacts("") }.to raise_error(ArgumentError)
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, contacts_api_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.contacts(tenant_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#contact" do
    let(:tenant_id)        { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:contact_id)       { "bd2270c3-8706-4c11-9cfb-000b551c3f51" }
    let(:contact_endpoint) { "https://api.xero.com/api.xro/2.0/Contacts/#{contact_id}" }
    let(:contact_payload) do
      {
        "Contacts" => [
          {
            "ContactID"       => contact_id,
            "ContactStatus"   => "ACTIVE",
            "Name"            => "ABC Limited",
            "FirstName"       => "Andrea",
            "LastName"        => "Dutchess",
            "EmailAddress"    => "a.dutchess@abclimited.com",
            "IsSupplier"      => false,
            "IsCustomer"      => true,
            "DefaultCurrency" => "NZD",
            "UpdatedDateUTC"  => "/Date(1488391422280+0000)/",
            "Addresses"       => [{ "AddressType" => "POBOX" }],
            "Phones"          => [{ "PhoneType" => "DEFAULT" }],
            "ContactPersons"  => [{ "FirstName" => "John", "LastName" => "Smith" }],
            "PaymentTerms"    => { "Bills" => { "Day" => 15, "Type" => "OFCURRENTMONTH" } }
          }
        ]
      }
    end

    it "sends the tenant-id header and returns a single XeroKiwi::Accounting::Contact" do
      stub = stub_request(:get, contact_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(contact_payload), headers: json_headers)

      contact = client.contact(tenant_id, contact_id)

      expect(stub).to have_been_requested
      expect(contact).to be_a(XeroKiwi::Accounting::Contact)
      expect(contact.contact_id).to eq(contact_id)
      expect(contact.name).to eq("ABC Limited")
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, contact_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(contact_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      expect(client.contact(connection, contact_id)).to be_a(XeroKiwi::Accounting::Contact)
    end

    it "raises ArgumentError when tenant_id is nil" do
      expect { client.contact(nil, contact_id) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when contact_id is nil" do
      expect { client.contact(tenant_id, nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when contact_id is an empty string" do
      expect { client.contact(tenant_id, "") }.to raise_error(ArgumentError)
    end

    it "raises ClientError on 404" do
      stub_request(:get, contact_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 404, body: '{"error":"not_found"}', headers: json_headers)

      expect { client.contact(tenant_id, contact_id) }.to raise_error(XeroKiwi::ClientError) do |error|
        expect(error.status).to eq(404)
      end
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, contact_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.contact(tenant_id, contact_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#contact_groups" do
    let(:tenant_id)                  { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:contact_groups_endpoint)    { "https://api.xero.com/api.xro/2.0/ContactGroups" }
    let(:contact_groups_payload) do
      {
        "ContactGroups" => [
          {
            "ContactGroupID" => "97bbd0e6-ab4d-4117-9304-d90dd4779199",
            "Name"           => "VIP Customers",
            "Status"         => "ACTIVE"
          }
        ]
      }
    end

    context "when talking to the live Xero API", vcr: { cassette_name: "contact_groups/list" } do
      it "returns parsed XeroKiwi::Accounting::ContactGroup objects" do
        expect(client.contact_groups(tenant_id)).to all(be_a(XeroKiwi::Accounting::ContactGroup))
      end

      it "decodes Xero's contact group schema correctly" do
        groups = client.contact_groups(tenant_id)
        expect(groups).not_to be_empty
        expect(groups.first).to have_attributes(
          contact_group_id: match(/\A[\w-]+\z/),
          name:             a_kind_of(String).and(satisfy { |s| !s.empty? }),
          status:           "ACTIVE"
        )
      end
    end

    it "sends the tenant-id header and returns XeroKiwi::Accounting::ContactGroup objects" do
      stub = stub_request(:get, contact_groups_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(contact_groups_payload), headers: json_headers)

      groups = client.contact_groups(tenant_id)

      expect(stub).to have_been_requested
      expect(groups).to all(be_a(XeroKiwi::Accounting::ContactGroup))
      expect(groups.first.name).to eq("VIP Customers")
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, contact_groups_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(contact_groups_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      expect(client.contact_groups(connection)).to all(be_a(XeroKiwi::Accounting::ContactGroup))
    end

    it "returns an empty array when no contact groups are present" do
      stub_request(:get, contact_groups_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump("ContactGroups" => []), headers: json_headers)

      expect(client.contact_groups(tenant_id)).to eq([])
    end

    it "raises ArgumentError when given nil" do
      expect { client.contact_groups(nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when given an empty string" do
      expect { client.contact_groups("") }.to raise_error(ArgumentError)
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, contact_groups_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.contact_groups(tenant_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#contact_group" do
    let(:tenant_id)              { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:contact_group_id)       { "97bbd0e6-ab4d-4117-9304-d90dd4779199" }
    let(:contact_group_endpoint) { "https://api.xero.com/api.xro/2.0/ContactGroups/#{contact_group_id}" }
    let(:contact_group_payload) do
      {
        "ContactGroups" => [
          {
            "ContactGroupID" => contact_group_id,
            "Name"           => "VIP Customers",
            "Status"         => "ACTIVE",
            "Contacts"       => [
              { "ContactID" => "9ce626d2-14ea-463c-9fff-6785ab5f9bfb", "Name" => "Boom FM" }
            ]
          }
        ]
      }
    end

    it "sends the tenant-id header and returns a single XeroKiwi::Accounting::ContactGroup" do
      stub = stub_request(:get, contact_group_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(contact_group_payload), headers: json_headers)

      group = client.contact_group(tenant_id, contact_group_id)

      expect(stub).to have_been_requested
      expect(group).to be_a(XeroKiwi::Accounting::ContactGroup)
      expect(group.contact_group_id).to eq(contact_group_id)
      expect(group.name).to eq("VIP Customers")
      expect(group.contacts.size).to eq(1)
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, contact_group_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(contact_group_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      expect(client.contact_group(connection, contact_group_id)).to be_a(XeroKiwi::Accounting::ContactGroup)
    end

    it "raises ArgumentError when tenant_id is nil" do
      expect { client.contact_group(nil, contact_group_id) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when contact_group_id is nil" do
      expect { client.contact_group(tenant_id, nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when contact_group_id is an empty string" do
      expect { client.contact_group(tenant_id, "") }.to raise_error(ArgumentError)
    end

    it "raises ClientError on 404" do
      stub_request(:get, contact_group_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 404, body: '{"error":"not_found"}', headers: json_headers)

      expect { client.contact_group(tenant_id, contact_group_id) }.to raise_error(XeroKiwi::ClientError) do |error|
        expect(error.status).to eq(404)
      end
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, contact_group_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.contact_group(tenant_id, contact_group_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#prepayments" do
    let(:tenant_id)             { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:prepayments_endpoint)  { "https://api.xero.com/api.xro/2.0/Prepayments" }
    let(:prepayments_payload) do
      {
        "Prepayments" => [
          {
            "PrepaymentID"   => "aea95d78-ea48-456b-9b08-6bc012600072",
            "Type"           => "RECEIVE-PREPAYMENT",
            "Contact"        => { "ContactID" => "c6c7b870", "Name" => "Mr Contact" },
            "Status"         => "PAID",
            "Total"          => "100.00",
            "UpdatedDateUTC" => "/Date(1222340661707+0000)/",
            "CurrencyCode"   => "NZD"
          }
        ]
      }
    end

    context "when talking to the live Xero API", vcr: { cassette_name: "prepayments/list" } do
      it "returns parsed XeroKiwi::Accounting::Prepayment objects" do
        result = client.prepayments(tenant_id)
        expect(result).to all(be_a(XeroKiwi::Accounting::Prepayment)).or eq([])
      end
    end

    it "sends the tenant-id header and returns XeroKiwi::Accounting::Prepayment objects" do
      stub = stub_request(:get, prepayments_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(prepayments_payload), headers: json_headers)

      prepayments = client.prepayments(tenant_id)

      expect(stub).to have_been_requested
      expect(prepayments).to all(be_a(XeroKiwi::Accounting::Prepayment))
      expect(prepayments.first.prepayment_id).to eq("aea95d78-ea48-456b-9b08-6bc012600072")
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, prepayments_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(prepayments_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      expect(client.prepayments(connection)).to all(be_a(XeroKiwi::Accounting::Prepayment))
    end

    it "returns an empty array when no prepayments are present" do
      stub_request(:get, prepayments_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump("Prepayments" => []), headers: json_headers)

      expect(client.prepayments(tenant_id)).to eq([])
    end

    it "raises ArgumentError when given nil" do
      expect { client.prepayments(nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when given an empty string" do
      expect { client.prepayments("") }.to raise_error(ArgumentError)
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, prepayments_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.prepayments(tenant_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#prepayment" do
    let(:tenant_id)            { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:prepayment_id)        { "aea95d78-ea48-456b-9b08-6bc012600072" }
    let(:prepayment_endpoint)  { "https://api.xero.com/api.xro/2.0/Prepayments/#{prepayment_id}" }
    let(:prepayment_payload) do
      {
        "Prepayments" => [
          {
            "PrepaymentID"   => prepayment_id,
            "Type"           => "RECEIVE-PREPAYMENT",
            "Contact"        => { "ContactID" => "c6c7b870", "Name" => "Mr Contact" },
            "Status"         => "PAID",
            "Total"          => "100.00",
            "UpdatedDateUTC" => "/Date(1222340661707+0000)/",
            "CurrencyCode"   => "NZD",
            "LineItems"      => [{ "Description" => "Consulting", "LineAmount" => "100.00" }]
          }
        ]
      }
    end

    it "sends the tenant-id header and returns a single XeroKiwi::Accounting::Prepayment" do
      stub = stub_request(:get, prepayment_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(prepayment_payload), headers: json_headers)

      prepayment = client.prepayment(tenant_id, prepayment_id)

      expect(stub).to have_been_requested
      expect(prepayment).to be_a(XeroKiwi::Accounting::Prepayment)
      expect(prepayment.prepayment_id).to eq(prepayment_id)
      expect(prepayment.total).to eq("100.00")
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, prepayment_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(prepayment_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      expect(client.prepayment(connection, prepayment_id)).to be_a(XeroKiwi::Accounting::Prepayment)
    end

    it "raises ArgumentError when tenant_id is nil" do
      expect { client.prepayment(nil, prepayment_id) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when prepayment_id is nil" do
      expect { client.prepayment(tenant_id, nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when prepayment_id is an empty string" do
      expect { client.prepayment(tenant_id, "") }.to raise_error(ArgumentError)
    end

    it "raises ClientError on 404" do
      stub_request(:get, prepayment_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 404, body: '{"error":"not_found"}', headers: json_headers)

      expect { client.prepayment(tenant_id, prepayment_id) }.to raise_error(XeroKiwi::ClientError) do |error|
        expect(error.status).to eq(404)
      end
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, prepayment_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.prepayment(tenant_id, prepayment_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#credit_notes" do
    let(:tenant_id)              { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:credit_notes_endpoint)  { "https://api.xero.com/api.xro/2.0/CreditNotes" }
    let(:credit_notes_payload) do
      {
        "CreditNotes" => [
          {
            "CreditNoteID"     => "aea95d78-ea48-456b-9b08-6bc012600072",
            "CreditNoteNumber" => "CN-0002",
            "Type"             => "ACCRECCREDIT",
            "Contact"          => { "ContactID" => "c6c7b870", "Name" => "Test" },
            "Status"           => "PAID",
            "Total"            => 100.00,
            "UpdatedDateUTC"   => "/Date(1290168061547+0000)/",
            "CurrencyCode"     => "NZD"
          }
        ]
      }
    end

    context "when talking to the live Xero API", vcr: { cassette_name: "credit_notes/list" } do
      it "returns parsed XeroKiwi::Accounting::CreditNote objects" do
        result = client.credit_notes(tenant_id)
        expect(result).to all(be_a(XeroKiwi::Accounting::CreditNote)).or eq([])
      end
    end

    it "sends the tenant-id header and returns XeroKiwi::Accounting::CreditNote objects" do
      stub = stub_request(:get, credit_notes_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(credit_notes_payload), headers: json_headers)

      credit_notes = client.credit_notes(tenant_id)

      expect(stub).to have_been_requested
      expect(credit_notes).to all(be_a(XeroKiwi::Accounting::CreditNote))
      expect(credit_notes.first.credit_note_id).to eq("aea95d78-ea48-456b-9b08-6bc012600072")
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, credit_notes_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(credit_notes_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      expect(client.credit_notes(connection)).to all(be_a(XeroKiwi::Accounting::CreditNote))
    end

    it "returns an empty array when no credit notes are present" do
      stub_request(:get, credit_notes_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump("CreditNotes" => []), headers: json_headers)

      expect(client.credit_notes(tenant_id)).to eq([])
    end

    it "raises ArgumentError when given nil" do
      expect { client.credit_notes(nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when given an empty string" do
      expect { client.credit_notes("") }.to raise_error(ArgumentError)
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, credit_notes_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.credit_notes(tenant_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#credit_note" do
    let(:tenant_id)             { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:credit_note_id)        { "aea95d78-ea48-456b-9b08-6bc012600072" }
    let(:credit_note_endpoint)  { "https://api.xero.com/api.xro/2.0/CreditNotes/#{credit_note_id}" }
    let(:credit_note_payload) do
      {
        "CreditNotes" => [
          {
            "CreditNoteID"     => credit_note_id,
            "CreditNoteNumber" => "CN-0002",
            "Type"             => "ACCRECCREDIT",
            "Contact"          => { "ContactID" => "c6c7b870", "Name" => "Test" },
            "Status"           => "PAID",
            "Total"            => 100.00,
            "UpdatedDateUTC"   => "/Date(1290168061547+0000)/",
            "CurrencyCode"     => "NZD",
            "LineItems"        => [{ "Description" => "Refund", "LineAmount" => 100.00 }]
          }
        ]
      }
    end

    it "sends the tenant-id header and returns a single XeroKiwi::Accounting::CreditNote" do
      stub = stub_request(:get, credit_note_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(credit_note_payload), headers: json_headers)

      cn = client.credit_note(tenant_id, credit_note_id)

      expect(stub).to have_been_requested
      expect(cn).to be_a(XeroKiwi::Accounting::CreditNote)
      expect(cn.credit_note_id).to eq(credit_note_id)
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, credit_note_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(credit_note_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      expect(client.credit_note(connection, credit_note_id)).to be_a(XeroKiwi::Accounting::CreditNote)
    end

    it "raises ArgumentError when tenant_id is nil" do
      expect { client.credit_note(nil, credit_note_id) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when credit_note_id is nil" do
      expect { client.credit_note(tenant_id, nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when credit_note_id is an empty string" do
      expect { client.credit_note(tenant_id, "") }.to raise_error(ArgumentError)
    end

    it "raises ClientError on 404" do
      stub_request(:get, credit_note_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 404, body: '{"error":"not_found"}', headers: json_headers)

      expect { client.credit_note(tenant_id, credit_note_id) }.to raise_error(XeroKiwi::ClientError) do |error|
        expect(error.status).to eq(404)
      end
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, credit_note_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.credit_note(tenant_id, credit_note_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#overpayments" do
    let(:tenant_id)              { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:overpayments_endpoint)  { "https://api.xero.com/api.xro/2.0/Overpayments" }
    let(:overpayments_payload) do
      {
        "Overpayments" => [
          {
            "OverpaymentID"  => "aea95d78-ea48-456b-9b08-6bc012600072",
            "Type"           => "RECEIVE-OVERPAYMENT",
            "Contact"        => { "ContactID" => "c6c7b870", "Name" => "Mr Contact" },
            "Status"         => "PAID",
            "Total"          => "100.00",
            "UpdatedDateUTC" => "/Date(1222340661707+0000)/",
            "CurrencyCode"   => "NZD"
          }
        ]
      }
    end

    context "when talking to the live Xero API", vcr: { cassette_name: "overpayments/list" } do
      it "returns parsed XeroKiwi::Accounting::Overpayment objects" do
        result = client.overpayments(tenant_id)
        expect(result).to all(be_a(XeroKiwi::Accounting::Overpayment)).or eq([])
      end
    end

    it "sends the tenant-id header and returns XeroKiwi::Accounting::Overpayment objects" do
      stub = stub_request(:get, overpayments_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(overpayments_payload), headers: json_headers)

      overpayments = client.overpayments(tenant_id)

      expect(stub).to have_been_requested
      expect(overpayments).to all(be_a(XeroKiwi::Accounting::Overpayment))
      expect(overpayments.first.overpayment_id).to eq("aea95d78-ea48-456b-9b08-6bc012600072")
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, overpayments_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(overpayments_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      expect(client.overpayments(connection)).to all(be_a(XeroKiwi::Accounting::Overpayment))
    end

    it "returns an empty array when no overpayments are present" do
      stub_request(:get, overpayments_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump("Overpayments" => []), headers: json_headers)

      expect(client.overpayments(tenant_id)).to eq([])
    end

    it "raises ArgumentError when given nil" do
      expect { client.overpayments(nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when given an empty string" do
      expect { client.overpayments("") }.to raise_error(ArgumentError)
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, overpayments_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.overpayments(tenant_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#overpayment" do
    let(:tenant_id)             { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:overpayment_id)        { "aea95d78-ea48-456b-9b08-6bc012600072" }
    let(:overpayment_endpoint)  { "https://api.xero.com/api.xro/2.0/Overpayments/#{overpayment_id}" }
    let(:overpayment_payload) do
      {
        "Overpayments" => [
          {
            "OverpaymentID"  => overpayment_id,
            "Type"           => "RECEIVE-OVERPAYMENT",
            "Contact"        => { "ContactID" => "c6c7b870", "Name" => "Mr Contact" },
            "Status"         => "PAID",
            "Total"          => "100.00",
            "UpdatedDateUTC" => "/Date(1222340661707+0000)/",
            "CurrencyCode"   => "NZD",
            "LineItems"      => [{ "Description" => "Overpayment", "LineAmount" => "100.00" }]
          }
        ]
      }
    end

    it "sends the tenant-id header and returns a single XeroKiwi::Accounting::Overpayment" do
      stub = stub_request(:get, overpayment_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(overpayment_payload), headers: json_headers)

      op = client.overpayment(tenant_id, overpayment_id)

      expect(stub).to have_been_requested
      expect(op).to be_a(XeroKiwi::Accounting::Overpayment)
      expect(op.overpayment_id).to eq(overpayment_id)
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, overpayment_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(overpayment_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      expect(client.overpayment(connection, overpayment_id)).to be_a(XeroKiwi::Accounting::Overpayment)
    end

    it "raises ArgumentError when tenant_id is nil" do
      expect { client.overpayment(nil, overpayment_id) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when overpayment_id is nil" do
      expect { client.overpayment(tenant_id, nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when overpayment_id is an empty string" do
      expect { client.overpayment(tenant_id, "") }.to raise_error(ArgumentError)
    end

    it "raises ClientError on 404" do
      stub_request(:get, overpayment_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 404, body: '{"error":"not_found"}', headers: json_headers)

      expect { client.overpayment(tenant_id, overpayment_id) }.to raise_error(XeroKiwi::ClientError) do |error|
        expect(error.status).to eq(404)
      end
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, overpayment_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.overpayment(tenant_id, overpayment_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#payments" do
    let(:tenant_id)           { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:payments_endpoint)   { "https://api.xero.com/api.xro/2.0/Payments" }
    let(:payments_payload) do
      {
        "Payments" => [
          {
            "PaymentID"      => "b26fd49a-cbae-470a-a8f8-bcbc119e0379",
            "Date"           => "/Date(1455667200000+0000)/",
            "Amount"         => 500.00,
            "Status"         => "AUTHORISED",
            "PaymentType"    => "ACCRECPAYMENT",
            "UpdatedDateUTC" => "/Date(1289572582537+0000)/",
            "Account"        => { "AccountID" => "ac993f75", "Code" => "090" },
            "Invoice"        => { "InvoiceID" => "6a539484", "InvoiceNumber" => "INV-0001" }
          }
        ]
      }
    end

    context "when talking to the live Xero API", vcr: { cassette_name: "payments/list" } do
      it "returns parsed XeroKiwi::Accounting::Payment objects" do
        result = client.payments(tenant_id)
        expect(result).to all(be_a(XeroKiwi::Accounting::Payment)).or eq([])
      end
    end

    it "sends the tenant-id header and returns XeroKiwi::Accounting::Payment objects" do
      stub = stub_request(:get, payments_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(payments_payload), headers: json_headers)

      payments = client.payments(tenant_id)

      expect(stub).to have_been_requested
      expect(payments).to all(be_a(XeroKiwi::Accounting::Payment))
      expect(payments.first.payment_id).to eq("b26fd49a-cbae-470a-a8f8-bcbc119e0379")
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, payments_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(payments_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      expect(client.payments(connection)).to all(be_a(XeroKiwi::Accounting::Payment))
    end

    it "returns an empty array when no payments are present" do
      stub_request(:get, payments_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump("Payments" => []), headers: json_headers)

      expect(client.payments(tenant_id)).to eq([])
    end

    it "raises ArgumentError when given nil" do
      expect { client.payments(nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when given an empty string" do
      expect { client.payments("") }.to raise_error(ArgumentError)
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, payments_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.payments(tenant_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#payment" do
    let(:tenant_id)         { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:payment_id)        { "b26fd49a-cbae-470a-a8f8-bcbc119e0379" }
    let(:payment_endpoint)  { "https://api.xero.com/api.xro/2.0/Payments/#{payment_id}" }
    let(:payment_payload) do
      {
        "Payments" => [
          {
            "PaymentID"      => payment_id,
            "Date"           => "/Date(1455667200000+0000)/",
            "Amount"         => 500.00,
            "Status"         => "AUTHORISED",
            "PaymentType"    => "ACCRECPAYMENT",
            "UpdatedDateUTC" => "/Date(1289572582537+0000)/",
            "Account"        => { "AccountID" => "ac993f75", "Code" => "090" },
            "Invoice"        => { "InvoiceID" => "6a539484", "InvoiceNumber" => "INV-0001" }
          }
        ]
      }
    end

    it "sends the tenant-id header and returns a single XeroKiwi::Accounting::Payment" do
      stub = stub_request(:get, payment_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(payment_payload), headers: json_headers)

      payment = client.payment(tenant_id, payment_id)

      expect(stub).to have_been_requested
      expect(payment).to be_a(XeroKiwi::Accounting::Payment)
      expect(payment.payment_id).to eq(payment_id)
      expect(payment.amount).to eq(500.00)
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, payment_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(payment_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      expect(client.payment(connection, payment_id)).to be_a(XeroKiwi::Accounting::Payment)
    end

    it "raises ArgumentError when tenant_id is nil" do
      expect { client.payment(nil, payment_id) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when payment_id is nil" do
      expect { client.payment(tenant_id, nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when payment_id is an empty string" do
      expect { client.payment(tenant_id, "") }.to raise_error(ArgumentError)
    end

    it "raises ClientError on 404" do
      stub_request(:get, payment_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 404, body: '{"error":"not_found"}', headers: json_headers)

      expect { client.payment(tenant_id, payment_id) }.to raise_error(XeroKiwi::ClientError) do |error|
        expect(error.status).to eq(404)
      end
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, payment_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.payment(tenant_id, payment_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#invoices" do
    let(:tenant_id)          { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:invoices_endpoint)  { "https://api.xero.com/api.xro/2.0/Invoices" }
    let(:invoices_payload) do
      {
        "Invoices" => [
          {
            "InvoiceID"      => "243216c5-369e-4056-ac67-05388f86dc81",
            "InvoiceNumber"  => "OIT00546",
            "Type"           => "ACCREC",
            "Contact"        => { "ContactID" => "025867f1", "Name" => "City Agency" },
            "Status"         => "AUTHORISED",
            "Total"          => "2025.00",
            "UpdatedDateUTC" => "/Date(1518685950940+0000)/",
            "CurrencyCode"   => "NZD",
            "AmountDue"      => "2025.00",
            "AmountPaid"     => "0.00"
          }
        ]
      }
    end

    context "when talking to the live Xero API", vcr: { cassette_name: "invoices/list" } do
      it "returns parsed XeroKiwi::Accounting::Invoice objects" do
        result = client.invoices(tenant_id)
        expect(result).to all(be_a(XeroKiwi::Accounting::Invoice)).or eq([])
      end
    end

    it "sends the tenant-id header and returns XeroKiwi::Accounting::Invoice objects" do
      stub = stub_request(:get, invoices_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(invoices_payload), headers: json_headers)

      invoices = client.invoices(tenant_id)

      expect(stub).to have_been_requested
      expect(invoices).to all(be_a(XeroKiwi::Accounting::Invoice))
      expect(invoices.first.invoice_id).to eq("243216c5-369e-4056-ac67-05388f86dc81")
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, invoices_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(invoices_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      expect(client.invoices(connection)).to all(be_a(XeroKiwi::Accounting::Invoice))
    end

    it "returns an empty array when no invoices are present" do
      stub_request(:get, invoices_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump("Invoices" => []), headers: json_headers)

      expect(client.invoices(tenant_id)).to eq([])
    end

    it "raises ArgumentError when given nil" do
      expect { client.invoices(nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when given an empty string" do
      expect { client.invoices("") }.to raise_error(ArgumentError)
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, invoices_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.invoices(tenant_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#invoice" do
    let(:tenant_id)         { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:invoice_id)        { "243216c5-369e-4056-ac67-05388f86dc81" }
    let(:invoice_endpoint)  { "https://api.xero.com/api.xro/2.0/Invoices/#{invoice_id}" }
    let(:invoice_payload) do
      {
        "Invoices" => [
          {
            "InvoiceID"      => invoice_id,
            "InvoiceNumber"  => "OIT00546",
            "Type"           => "ACCREC",
            "Contact"        => { "ContactID" => "025867f1", "Name" => "City Agency" },
            "Status"         => "AUTHORISED",
            "Total"          => "2025.00",
            "UpdatedDateUTC" => "/Date(1518685950940+0000)/",
            "CurrencyCode"   => "NZD",
            "LineItems"      => [{ "Description" => "Consulting", "LineAmount" => "1800.00" }],
            "Payments"       => [{ "PaymentID" => "0d666415", "Amount" => "1000.00" }],
            "AmountDue"      => "1025.00",
            "AmountPaid"     => "1000.00"
          }
        ]
      }
    end

    it "sends the tenant-id header and returns a single XeroKiwi::Accounting::Invoice" do
      stub = stub_request(:get, invoice_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(invoice_payload), headers: json_headers)

      inv = client.invoice(tenant_id, invoice_id)

      expect(stub).to have_been_requested
      expect(inv).to be_a(XeroKiwi::Accounting::Invoice)
      expect(inv.invoice_id).to eq(invoice_id)
      expect(inv.invoice_number).to eq("OIT00546")
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, invoice_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(invoice_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      expect(client.invoice(connection, invoice_id)).to be_a(XeroKiwi::Accounting::Invoice)
    end

    it "raises ArgumentError when tenant_id is nil" do
      expect { client.invoice(nil, invoice_id) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when invoice_id is nil" do
      expect { client.invoice(tenant_id, nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when invoice_id is an empty string" do
      expect { client.invoice(tenant_id, "") }.to raise_error(ArgumentError)
    end

    it "raises ClientError on 404" do
      stub_request(:get, invoice_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 404, body: '{"error":"not_found"}', headers: json_headers)

      expect { client.invoice(tenant_id, invoice_id) }.to raise_error(XeroKiwi::ClientError) do |error|
        expect(error.status).to eq(404)
      end
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, invoice_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.invoice(tenant_id, invoice_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#online_invoice_url" do
    let(:tenant_id)                   { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:invoice_id)                  { "243216c5-369e-4056-ac67-05388f86dc81" }
    let(:online_invoice_endpoint)     { "https://api.xero.com/api.xro/2.0/Invoices/#{invoice_id}/OnlineInvoice" }
    let(:online_invoice_url_value)    { "https://in.xero.com/iztKMjyAEJT7MVnmruxgCdIJUDStfRgmtdQSIW13" }
    let(:online_invoice_payload) do
      { "OnlineInvoices" => [{ "OnlineInvoiceUrl" => online_invoice_url_value }] }
    end

    it "returns the online invoice URL string" do
      stub_request(:get, online_invoice_endpoint)
        .with(headers: { "Authorization" => "Bearer #{access_token}", "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(online_invoice_payload), headers: json_headers)

      expect(client.online_invoice_url(tenant_id, invoice_id)).to eq(online_invoice_url_value)
    end

    it "returns nil when the response has no OnlineInvoices" do
      stub_request(:get, online_invoice_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump({}), headers: json_headers)

      expect(client.online_invoice_url(tenant_id, invoice_id)).to be_nil
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, online_invoice_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(online_invoice_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      expect(client.online_invoice_url(connection, invoice_id)).to eq(online_invoice_url_value)
    end

    it "raises ArgumentError when tenant_id is nil" do
      expect { client.online_invoice_url(nil, invoice_id) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when invoice_id is nil" do
      expect { client.online_invoice_url(tenant_id, nil) }.to raise_error(ArgumentError)
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, online_invoice_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.online_invoice_url(tenant_id, invoice_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#branding_themes" do
    let(:tenant_id)                { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:branding_themes_endpoint) { "https://api.xero.com/api.xro/2.0/BrandingThemes" }

    let(:branding_themes_payload) do
      {
        "BrandingThemes" => [
          {
            "BrandingThemeID" => "dfe23d27-a3a6-4ef3-a5ca-b9e02b142dde",
            "Name"            => "Special Projects",
            "LogoUrl"         => "https://in.xero.com/logo?id=abc123",
            "Type"            => "INVOICE",
            "SortOrder"       => 1,
            "CreatedDateUTC"  => "/Date(946684800000+0000)/"
          }
        ]
      }
    end

    context "when talking to the live Xero API", vcr: { cassette_name: "branding_themes/list" } do
      it "returns parsed XeroKiwi::Accounting::BrandingTheme objects" do
        expect(client.branding_themes(tenant_id)).to all(be_a(XeroKiwi::Accounting::BrandingTheme))
      end

      it "decodes Xero's branding theme schema correctly" do
        themes = client.branding_themes(tenant_id)
        expect(themes).not_to be_empty
        expect(themes.first).to have_attributes(
          branding_theme_id: match(/\A[\w-]+\z/),
          name:              a_kind_of(String).and(satisfy { |s| !s.empty? }),
          type:              a_kind_of(String),
          sort_order:        a_kind_of(Integer),
          created_date_utc:  a_kind_of(Time).and(have_attributes(utc_offset: 0))
        )
      end
    end

    it "sends the tenant-id header and returns XeroKiwi::Accounting::BrandingTheme objects" do
      stub = stub_request(:get, branding_themes_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(branding_themes_payload), headers: json_headers)

      themes = client.branding_themes(tenant_id)

      expect(stub).to have_been_requested
      expect(themes).to all(be_a(XeroKiwi::Accounting::BrandingTheme))
      expect(themes.first.name).to eq("Special Projects")
      expect(themes.first.branding_theme_id).to eq("dfe23d27-a3a6-4ef3-a5ca-b9e02b142dde")
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, branding_themes_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(branding_themes_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      themes = client.branding_themes(connection)

      expect(themes).to all(be_a(XeroKiwi::Accounting::BrandingTheme))
    end

    it "returns an empty array when no branding themes are present" do
      stub_request(:get, branding_themes_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump("BrandingThemes" => []), headers: json_headers)

      expect(client.branding_themes(tenant_id)).to eq([])
    end

    it "raises ArgumentError when given nil" do
      expect { client.branding_themes(nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when given an empty string" do
      expect { client.branding_themes("") }.to raise_error(ArgumentError)
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, branding_themes_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.branding_themes(tenant_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#branding_theme" do
    let(:tenant_id)              { ENV.fetch("XERO_TENANT_ID", "70784a63-d24b-46a9-a4db-0e70a274b056") }
    let(:branding_theme_id)      { "dfe23d27-a3a6-4ef3-a5ca-b9e02b142dde" }
    let(:branding_theme_endpoint) { "https://api.xero.com/api.xro/2.0/BrandingThemes/#{branding_theme_id}" }

    let(:branding_theme_payload) do
      {
        "BrandingThemes" => [
          {
            "BrandingThemeID" => branding_theme_id,
            "Name"            => "Special Projects",
            "LogoUrl"         => "https://in.xero.com/logo?id=abc123",
            "Type"            => "INVOICE",
            "SortOrder"       => 1,
            "CreatedDateUTC"  => "/Date(946684800000+0000)/"
          }
        ]
      }
    end

    it "sends the tenant-id header and returns a single XeroKiwi::Accounting::BrandingTheme" do
      stub = stub_request(:get, branding_theme_endpoint)
             .with(
               headers: {
                 "Authorization"  => "Bearer #{access_token}",
                 "Xero-Tenant-Id" => tenant_id
               }
             )
             .to_return(status: 200, body: JSON.dump(branding_theme_payload), headers: json_headers)

      theme = client.branding_theme(tenant_id, branding_theme_id)

      expect(stub).to have_been_requested
      expect(theme).to be_a(XeroKiwi::Accounting::BrandingTheme)
      expect(theme.branding_theme_id).to eq(branding_theme_id)
      expect(theme.name).to eq("Special Projects")
    end

    it "accepts a XeroKiwi::Connection and uses its tenant_id" do
      stub_request(:get, branding_theme_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(branding_theme_payload), headers: json_headers)

      connection = XeroKiwi::Connection.new(
        "id"         => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        "tenantId"   => tenant_id,
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      theme = client.branding_theme(connection, branding_theme_id)

      expect(theme).to be_a(XeroKiwi::Accounting::BrandingTheme)
    end

    it "raises ArgumentError when tenant_id is nil" do
      expect { client.branding_theme(nil, branding_theme_id) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when branding_theme_id is nil" do
      expect { client.branding_theme(tenant_id, nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when branding_theme_id is an empty string" do
      expect { client.branding_theme(tenant_id, "") }.to raise_error(ArgumentError)
    end

    it "raises ClientError on 404" do
      stub_request(:get, branding_theme_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 404, body: '{"error":"not_found"}', headers: json_headers)

      expect { client.branding_theme(tenant_id, branding_theme_id) }.to raise_error(XeroKiwi::ClientError) do |error|
        expect(error.status).to eq(404)
      end
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, branding_theme_endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.branding_theme(tenant_id, branding_theme_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "#delete_connection" do
    let(:connection_id)        { "e1eede29-f875-4a5d-8470-17f6a29a88b1" }
    let(:delete_endpoint)      { "https://api.xero.com/connections/#{connection_id}" }

    it "DELETEs /connections/:id with the bearer token and returns true" do
      stub = stub_request(:delete, delete_endpoint)
             .with(headers: { "Authorization" => "Bearer #{access_token}" })
             .to_return(status: 204, body: "")

      expect(client.delete_connection(connection_id)).to be true
      expect(stub).to have_been_requested
    end

    it "accepts a XeroKiwi::Connection and uses its id" do
      stub_request(:delete, delete_endpoint).to_return(status: 204, body: "")

      connection = XeroKiwi::Connection.new(
        "id"         => connection_id,
        "tenantId"   => "70784a63-d24b-46a9-a4db-0e70a274b056",
        "tenantType" => "ORGANISATION",
        "tenantName" => "Maple Florists Ltd"
      )

      expect(client.delete_connection(connection)).to be true
      expect(WebMock).to have_requested(:delete, delete_endpoint)
    end

    it "raises ArgumentError when given nil" do
      expect { client.delete_connection(nil) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when given an empty string" do
      expect { client.delete_connection("") }.to raise_error(ArgumentError)
    end

    it "raises ClientError on 404 (connection already gone)" do
      stub_request(:delete, delete_endpoint)
        .to_return(status: 404, body: '{"error":"not_found"}', headers: json_headers)

      expect { client.delete_connection(connection_id) }.to raise_error(XeroKiwi::ClientError) do |error|
        expect(error.status).to eq(404)
      end
    end

    it "raises AuthenticationError on 401" do
      stub_request(:delete, delete_endpoint)
        .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

      expect { client.delete_connection(connection_id) }.to raise_error(XeroKiwi::AuthenticationError)
    end
  end

  describe "token refresh" do
    let(:refresh_endpoint) { "https://identity.xero.com/connect/token" }
    let(:client_id)        { "client_xyz" }
    let(:client_secret)    { "secret_abc" }
    let(:refreshed_tokens) { [] }

    let(:refresh_response_body) do
      JSON.dump(
        "access_token"  => "new_access_token",
        "refresh_token" => "new_refresh_token",
        "expires_in"    => 1800,
        "token_type"    => "Bearer",
        "scope"         => "offline_access accounting.transactions"
      )
    end

    def build_client(access_token: "old_access_token",
                     refresh_token: "old_refresh_token",
                     expires_at: Time.now + 1800,
                     client_id: "client_xyz",
                     client_secret: "secret_abc")
      described_class.new(
        access_token:     access_token,
        refresh_token:    refresh_token,
        expires_at:       expires_at,
        client_id:        client_id,
        client_secret:    client_secret,
        on_token_refresh: ->(token) { refreshed_tokens << token },
        retry_options:    { interval: 0, interval_randomness: 0, backoff_factor: 1, max: 0 }
      )
    end

    describe "#can_refresh?" do
      it "is true when client_id, client_secret, and refresh_token are all present" do
        expect(build_client.can_refresh?).to be true
      end

      it "is false without client credentials" do
        expect(build_client(client_id: nil).can_refresh?).to       be false
        expect(build_client(client_secret: nil).can_refresh?).to   be false
      end

      it "is false without a refresh token" do
        expect(build_client(refresh_token: nil).can_refresh?).to be false
      end
    end

    describe "#refresh_token!" do
      it "POSTs to the identity endpoint and replaces the in-memory token" do
        stub_request(:post, refresh_endpoint)
          .to_return(status: 200, body: refresh_response_body, headers: json_headers)

        client    = build_client
        new_token = client.refresh_token!

        expect(new_token.access_token).to  eq("new_access_token")
        expect(new_token.refresh_token).to eq("new_refresh_token")
        expect(client.token).to eq(new_token)
      end

      it "fires the on_token_refresh callback with the new token" do
        stub_request(:post, refresh_endpoint)
          .to_return(status: 200, body: refresh_response_body, headers: json_headers)

        client = build_client
        client.refresh_token!

        expect(refreshed_tokens.size).to                  eq(1)
        expect(refreshed_tokens.first.access_token).to    eq("new_access_token")
      end

      it "uses the new bearer token on subsequent API calls" do
        stub_request(:post, refresh_endpoint)
          .to_return(status: 200, body: refresh_response_body, headers: json_headers)

        client = build_client
        client.refresh_token!

        api_stub = stub_request(:get, connections_endpoint)
                   .with(headers: { "Authorization" => "Bearer new_access_token" })
                   .to_return(status: 200, body: "[]", headers: json_headers)

        client.connections

        expect(api_stub).to have_been_requested
      end

      it "raises TokenRefreshError when the client has no refresh capability" do
        client = build_client(refresh_token: nil)
        expect { client.refresh_token! }.to raise_error(XeroKiwi::TokenRefreshError)
      end

      it "raises TokenRefreshError when Xero rejects the refresh" do
        stub_request(:post, refresh_endpoint)
          .to_return(
            status:  400,
            body:    JSON.dump("error" => "invalid_grant"),
            headers: json_headers
          )

        expect { build_client.refresh_token! }.to raise_error(XeroKiwi::TokenRefreshError)
      end
    end

    describe "proactive refresh before a request" do
      it "refreshes when the token is expiring within the default window" do
        refresh_stub = stub_request(:post, refresh_endpoint)
                       .to_return(status: 200, body: refresh_response_body, headers: json_headers)
        stub_request(:get, connections_endpoint)
          .with(headers: { "Authorization" => "Bearer new_access_token" })
          .to_return(status: 200, body: "[]", headers: json_headers)

        client = build_client(expires_at: Time.now + 30) # inside 60s window
        client.connections

        expect(refresh_stub).to have_been_requested.once
      end

      it "does NOT refresh when the token is comfortably fresh" do
        stub_request(:get, connections_endpoint)
          .with(headers: { "Authorization" => "Bearer old_access_token" })
          .to_return(status: 200, body: "[]", headers: json_headers)
        refresh_stub = stub_request(:post, refresh_endpoint)

        client = build_client(expires_at: Time.now + 1800)
        client.connections

        expect(refresh_stub).not_to have_been_requested
      end

      it "does NOT refresh when the client has no refresh capability, even if expiring" do
        stub_request(:get, connections_endpoint)
          .to_return(status: 200, body: "[]", headers: json_headers)
        refresh_stub = stub_request(:post, refresh_endpoint)

        client = build_client(refresh_token: nil, expires_at: Time.now + 30)
        client.connections

        expect(refresh_stub).not_to have_been_requested
      end
    end

    describe "#revoke_token!" do
      let(:revoke_endpoint) { "https://identity.xero.com/connect/revocation" }

      it "POSTs the refresh token to Xero's revocation endpoint and returns true" do
        stub = stub_request(:post, revoke_endpoint)
               .with(body: { token: "old_refresh_token", token_type_hint: "refresh_token" })
               .to_return(status: 200, body: "")

        expect(build_client.revoke_token!).to be true
        expect(stub).to have_been_requested
      end

      it "raises TokenRefreshError when the client has no refresh capability" do
        client = build_client(refresh_token: nil)
        expect { client.revoke_token! }.to raise_error(XeroKiwi::TokenRefreshError)
      end

      it "raises TokenRefreshError when the client has no client credentials" do
        client = build_client(client_id: nil)
        expect { client.revoke_token! }.to raise_error(XeroKiwi::TokenRefreshError)
      end

      it "propagates AuthenticationError on 401 from the revoke endpoint" do
        stub_request(:post, revoke_endpoint)
          .to_return(status: 401, body: JSON.dump("error" => "invalid_client"), headers: json_headers)

        expect { build_client.revoke_token! }.to raise_error(XeroKiwi::AuthenticationError)
      end
    end

    describe "reactive refresh on 401" do
      it "refreshes and retries the request once when the API returns 401" do
        stub_request(:post, refresh_endpoint)
          .to_return(status: 200, body: refresh_response_body, headers: json_headers)
        stub_request(:get, connections_endpoint).to_return(
          { status: 401, body: '{"error":"invalid_token"}', headers: json_headers },
          { status: 200, body: "[]",                        headers: json_headers }
        )

        expect(build_client.connections).to eq([])
        expect(WebMock).to have_requested(:get,  connections_endpoint).twice
        expect(WebMock).to have_requested(:post, refresh_endpoint).once
      end

      it "raises AuthenticationError after one failed retry (no infinite loop)" do
        stub_request(:post, refresh_endpoint)
          .to_return(status: 200, body: refresh_response_body, headers: json_headers)
        stub_request(:get, connections_endpoint)
          .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)

        expect { build_client.connections }.to raise_error(XeroKiwi::AuthenticationError)
        expect(WebMock).to have_requested(:get,  connections_endpoint).twice
        expect(WebMock).to have_requested(:post, refresh_endpoint).once
      end

      it "does NOT attempt a refresh on 401 when the client has no refresh capability" do
        stub_request(:get, connections_endpoint)
          .to_return(status: 401, body: '{"error":"invalid_token"}', headers: json_headers)
        refresh_stub = stub_request(:post, refresh_endpoint)

        client = build_client(client_id: nil)
        expect { client.connections }.to raise_error(XeroKiwi::AuthenticationError)
        expect(refresh_stub).not_to have_been_requested
      end
    end
  end
end
