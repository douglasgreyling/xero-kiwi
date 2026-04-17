# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::TrackingCategory do
  let(:full_attrs) do
    {
      "TrackingCategoryID" => "e2f2f732-e92a-4f3a-9c4d-ee4da0182a13",
      "TrackingOptionID"   => "3f05cdf9-246b-46a2-bf6f-441da1b09b89",
      "Name"               => "Activity/Workstream",
      "Option"             => "Onsite consultancy"
    }
  end

  describe "#initialize" do
    it "maps all attributes" do
      tc = described_class.new(full_attrs)

      expect(tc).to have_attributes(
        tracking_category_id: "e2f2f732-e92a-4f3a-9c4d-ee4da0182a13",
        tracking_option_id:   "3f05cdf9-246b-46a2-bf6f-441da1b09b89",
        name:                 "Activity/Workstream",
        option:               "Onsite consultancy"
      )
    end

    it "handles missing IDs gracefully" do
      tc = described_class.new({ "Name" => "Region", "Option" => "North" })

      expect(tc.tracking_category_id).to be_nil
      expect(tc.name).to eq("Region")
      expect(tc.option).to eq("North")
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      tc   = described_class.new(full_attrs)
      hash = tc.to_h

      expect(hash[:name]).to eq("Activity/Workstream")
      expect(hash.keys).to match_array(described_class.attributes.keys)
    end
  end

  describe "equality" do
    it "considers tracking categories with the same attributes equal" do
      a = described_class.new(full_attrs)
      b = described_class.new(full_attrs)

      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
    end

    it "considers tracking categories with different attributes unequal" do
      a = described_class.new(full_attrs)
      b = described_class.new(full_attrs.merge("Option" => "Other"))

      expect(a).not_to eq(b)
    end
  end

  describe "#inspect" do
    it "includes the name and option" do
      tc = described_class.new(full_attrs)

      expect(tc.inspect).to include("name=")
      expect(tc.inspect).to include("option=")
    end
  end
end
