# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::TrackingOption do
  subject(:option) { described_class.new(attrs) }

  let(:attrs) do
    {
      "TrackingOptionID" => "3f05cdf9-246b-46a2-bf6f-441da1b09b89",
      "Name"             => "Eastside",
      "Status"           => "ACTIVE"
    }
  end

  describe "#initialize" do
    it "maps all attributes" do
      expect(option).to have_attributes(
        tracking_option_id: "3f05cdf9-246b-46a2-bf6f-441da1b09b89",
        name:               "Eastside",
        status:             "ACTIVE"
      )
    end

    it "leaves missing attributes nil" do
      expect(described_class.new({}).name).to be_nil
    end
  end

  describe "#active?" do
    it "is true for an ACTIVE option" do
      expect(option.active?).to be(true)
    end

    it "is false for a DELETED option" do
      expect(described_class.new(attrs.merge("Status" => "DELETED")).active?).to be(false)
    end
  end

  describe "equality" do
    it "matches on tracking_option_id alone" do
      expect(described_class.new(attrs.merge("Name" => "Renamed"))).to eq(option)
    end
  end
end
