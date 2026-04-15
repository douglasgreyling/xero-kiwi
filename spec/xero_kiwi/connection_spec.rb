# frozen_string_literal: true

RSpec.describe XeroKiwi::Connection do
  let(:payload) do
    {
      "id"             => "e1eede29-f875-4a5d-8470-17f6a29a88b1",
      "authEventId"    => "d99ecdfe-391d-43d2-b834-17636ba90e8d",
      "tenantId"       => "70784a63-d24b-46a9-a4db-0e70a274b056",
      "tenantType"     => "ORGANISATION",
      "tenantName"     => "Maple Florists Ltd",
      "createdDateUtc" => "2019-07-09T23:40:30.1833130",
      "updatedDateUtc" => "2020-05-15T01:35:13.8491980"
    }
  end

  describe "#initialize" do
    subject(:connection) { described_class.new(payload) }

    it "exposes scalar attributes" do
      expect(connection).to have_attributes(
        id:            "e1eede29-f875-4a5d-8470-17f6a29a88b1",
        auth_event_id: "d99ecdfe-391d-43d2-b834-17636ba90e8d",
        tenant_id:     "70784a63-d24b-46a9-a4db-0e70a274b056",
        tenant_type:   "ORGANISATION",
        tenant_name:   "Maple Florists Ltd"
      )
    end

    it "parses Xero's tz-less UTC timestamps as UTC Time objects" do
      expect(connection.created_date_utc).to be_a(Time)
      expect(connection.created_date_utc.utc_offset).to eq(0)
      expect(connection.created_date_utc.iso8601).to eq("2019-07-09T23:40:30Z")
    end

    it "tolerates missing timestamps" do
      conn = described_class.new(payload.merge("createdDateUtc" => nil, "updatedDateUtc" => ""))
      expect(conn.created_date_utc).to be_nil
      expect(conn.updated_date_utc).to be_nil
    end

    it "accepts symbol-keyed attribute hashes too" do
      symbolised = payload.transform_keys(&:to_sym)
      expect(described_class.new(symbolised).id).to eq(payload["id"])
    end
  end

  describe "#organisation? / #practice?" do
    it "is an organisation when tenantType is ORGANISATION" do
      connection = described_class.new(payload)
      expect(connection).to be_organisation
      expect(connection).not_to be_practice
    end

    it "is a practice when tenantType is PRACTICE" do
      practice = described_class.new(payload.merge("tenantType" => "PRACTICE"))
      expect(practice).to be_practice
      expect(practice).not_to be_organisation
    end
  end

  describe "equality" do
    it "compares by id" do
      a = described_class.new(payload)
      b = described_class.new(payload.merge("tenantName" => "Different Name"))
      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
    end
  end

  describe ".from_response" do
    it "wraps an array of attribute hashes" do
      result = described_class.from_response([payload, payload.merge("id" => "other")])
      expect(result.map(&:id)).to eq([payload["id"], "other"])
    end

    it "tolerates a single hash payload" do
      expect(described_class.from_response(payload).first).to be_a(described_class)
    end

    it "returns an empty array for nil" do
      expect(described_class.from_response(nil)).to eq([])
    end
  end
end
