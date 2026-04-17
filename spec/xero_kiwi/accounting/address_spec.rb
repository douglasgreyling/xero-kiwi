# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::Address do
  let(:full_attrs) do
    {
      "AddressType"  => "STREET",
      "AddressLine1" => "123 Main St",
      "AddressLine2" => "Suite 4",
      "AddressLine3" => nil,
      "AddressLine4" => nil,
      "City"         => "Auckland",
      "Region"       => "Auckland",
      "PostalCode"   => "1010",
      "Country"      => "NZ",
      "AttentionTo"  => "Jane Doe"
    }
  end

  describe "#initialize" do
    it "maps all attributes" do
      address = described_class.new(full_attrs)

      expect(address).to have_attributes(
        address_type:   "STREET",
        address_line_1: "123 Main St",
        address_line_2: "Suite 4",
        address_line_3: nil,
        address_line_4: nil,
        city:           "Auckland",
        region:         "Auckland",
        postal_code:    "1010",
        country:        "NZ",
        attention_to:   "Jane Doe"
      )
    end
  end

  describe "type predicates" do
    it "street? returns true for STREET" do
      expect(described_class.new("AddressType" => "STREET").street?).to be true
    end

    it "pobox? returns true for POBOX" do
      expect(described_class.new("AddressType" => "POBOX").pobox?).to be true
    end

    it "delivery? returns true for DELIVERY" do
      expect(described_class.new("AddressType" => "DELIVERY").delivery?).to be true
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      address = described_class.new(full_attrs)
      expect(address.to_h[:address_type]).to eq("STREET")
      expect(address.to_h[:city]).to eq("Auckland")
      expect(address.to_h.keys).to match_array(described_class.attributes.keys)
    end
  end

  describe "equality" do
    it "considers addresses with the same attributes equal" do
      a = described_class.new(full_attrs)
      b = described_class.new(full_attrs)

      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
    end

    it "considers addresses with different attributes unequal" do
      a = described_class.new(full_attrs)
      b = described_class.new(full_attrs.merge("City" => "Wellington"))

      expect(a).not_to eq(b)
    end
  end
end
