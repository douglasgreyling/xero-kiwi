# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::TrackingCategory do
  subject(:category) { described_class.new(attrs) }

  let(:attrs) do
    {
      "TrackingCategoryID" => "e2f2f732-e92a-4f3a-9c4d-ee4da0182a13",
      "Name"               => "Region",
      "Status"             => "ACTIVE",
      "Options"            => [
        { "TrackingOptionID" => "3f05cdf9-246b-46a2-bf6f-441da1b09b89", "Name" => "Eastside", "Status" => "ACTIVE" },
        { "TrackingOptionID" => "8a7f1b2c-1111-2222-3333-444455556666", "Name" => "Westside", "Status" => "DELETED" }
      ]
    }
  end

  describe "#initialize" do
    it "maps the category's own attributes" do
      expect(category).to have_attributes(
        tracking_category_id: "e2f2f732-e92a-4f3a-9c4d-ee4da0182a13",
        name:                 "Region",
        status:               "ACTIVE"
      )
    end

    it "hydrates Options into TrackingOption objects" do
      expect(category.options).to all(be_a(XeroKiwi::Accounting::TrackingOption))
    end

    it "maps each option's attributes" do
      expect(category.options.first).to have_attributes(
        tracking_option_id: "3f05cdf9-246b-46a2-bf6f-441da1b09b89",
        name:               "Eastside",
        status:             "ACTIVE"
      )
    end

    it "defaults Options to an empty array when absent" do
      expect(described_class.new("TrackingCategoryID" => "x").options).to eq([])
    end
  end

  describe "#active?" do
    it "is true for an ACTIVE category" do
      expect(category.active?).to be(true)
    end

    it "is false for an ARCHIVED category" do
      expect(described_class.new(attrs.merge("Status" => "ARCHIVED")).active?).to be(false)
    end
  end

  describe ".from_response" do
    it "unwraps the TrackingCategories payload key" do
      expect(described_class.from_response("TrackingCategories" => [attrs]).first).to eq(category)
    end

    it "returns an empty array when the key is missing" do
      expect(described_class.from_response({})).to eq([])
    end
  end

  describe "equality" do
    it "matches on tracking_category_id alone" do
      expect(described_class.new(attrs.merge("Name" => "Renamed"))).to eq(category)
    end
  end

  # The nested assignment shape shares a name and an ID field with this one
  # and nothing else. Keeping them distinct is the whole point of the split.
  describe "against Accounting::Tracking" do
    it "is a different class from the nested assignment shape" do
      expect(described_class).not_to eq(XeroKiwi::Accounting::Tracking)
    end

    it "does not carry the assignment's chosen-option fields" do
      expect(category).not_to respond_to(:tracking_option_id)
    end
  end
end
