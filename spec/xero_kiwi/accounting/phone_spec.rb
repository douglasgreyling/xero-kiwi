# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::Phone do
  let(:full_attrs) do
    {
      "PhoneType"        => "DEFAULT",
      "PhoneNumber"      => "1234567",
      "PhoneAreaCode"    => "09",
      "PhoneCountryCode" => "64"
    }
  end

  describe "#initialize" do
    it "maps all attributes" do
      phone = described_class.new(full_attrs)

      expect(phone).to have_attributes(
        phone_type:         "DEFAULT",
        phone_number:       "1234567",
        phone_area_code:    "09",
        phone_country_code: "64"
      )
    end
  end

  describe "type predicates" do
    it "default? returns true for DEFAULT" do
      expect(described_class.new("PhoneType" => "DEFAULT").default?).to be true
    end

    it "mobile? returns true for MOBILE" do
      expect(described_class.new("PhoneType" => "MOBILE").mobile?).to be true
    end

    it "fax? returns true for FAX" do
      expect(described_class.new("PhoneType" => "FAX").fax?).to be true
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      phone = described_class.new(full_attrs)
      expect(phone.to_h[:phone_type]).to eq("DEFAULT")
      expect(phone.to_h.keys).to match_array(described_class::ATTRIBUTES.keys)
    end
  end

  describe "equality" do
    it "considers phones with the same attributes equal" do
      a = described_class.new(full_attrs)
      b = described_class.new(full_attrs)

      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
    end
  end
end
