# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::LineItem do
  let(:full_attrs) do
    {
      "LineItemID"     => "52208ff9-528a-4985-a9ad-b2b1d4210e38",
      "Description"    => "Onsite project management",
      "Quantity"       => "1.0000",
      "UnitAmount"     => "1800.00",
      "ItemCode"       => "12",
      "AccountCode"    => "200",
      "AccountId"      => "4f2a3169-8454-4012-a642-05a88ef32982",
      "TaxType"        => "OUTPUT",
      "TaxAmount"      => "225.00",
      "LineAmount"     => "1800.00",
      "DiscountRate"   => "20",
      "DiscountAmount" => nil,
      "Tracking"       => [
        {
          "TrackingCategoryID" => "e2f2f732-e92a-4f3a-9c4d-ee4da0182a13",
          "Name"               => "Activity/Workstream",
          "Option"             => "Onsite consultancy"
        }
      ],
      "Item"           => {
        "ItemID" => "fed07c3f-ca77-4820-b4df-304048b3266f",
        "Name"   => "Test item",
        "Code"   => "12"
      }
    }
  end

  describe "#initialize" do
    subject(:item) { described_class.new(full_attrs) }

    it "maps all scalar attributes" do
      expect(item).to have_attributes(
        line_item_id:    "52208ff9-528a-4985-a9ad-b2b1d4210e38",
        description:     "Onsite project management",
        quantity:        "1.0000",
        unit_amount:     "1800.00",
        item_code:       "12",
        account_code:    "200",
        account_id:      "4f2a3169-8454-4012-a642-05a88ef32982",
        tax_type:        "OUTPUT",
        tax_amount:      "225.00",
        line_amount:     "1800.00",
        discount_rate:   "20",
        discount_amount: nil
      )
    end

    it "wraps tracking as XeroKiwi::Accounting::TrackingCategory objects" do
      expect(item.tracking).to all(be_a(XeroKiwi::Accounting::TrackingCategory))
      expect(item.tracking.first.name).to eq("Activity/Workstream")
      expect(item.tracking.first.option).to eq("Onsite consultancy")
      expect(item.tracking.first.tracking_category_id).to eq("e2f2f732-e92a-4f3a-9c4d-ee4da0182a13")
    end

    it "preserves item as a raw hash" do
      expect(item.item).to eq(
        "ItemID" => "fed07c3f-ca77-4820-b4df-304048b3266f",
        "Name"   => "Test item",
        "Code"   => "12"
      )
    end

    it "defaults tracking to an empty array when absent" do
      item = described_class.new("Description" => "Test")
      expect(item.tracking).to eq([])
    end

    it "handles nil item gracefully" do
      item = described_class.new("Description" => "Test")
      expect(item.item).to be_nil
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      item = described_class.new(full_attrs)
      hash = item.to_h

      expect(hash[:description]).to eq("Onsite project management")
      expect(hash[:line_item_id]).to eq("52208ff9-528a-4985-a9ad-b2b1d4210e38")
      expect(hash.keys).to match_array(described_class::ATTRIBUTES.keys)
    end
  end

  describe "equality" do
    it "considers items with the same attributes equal" do
      a = described_class.new(full_attrs)
      b = described_class.new(full_attrs)

      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
    end

    it "considers items with different attributes unequal" do
      a = described_class.new(full_attrs)
      b = described_class.new(full_attrs.merge("Description" => "Other"))

      expect(a).not_to eq(b)
    end
  end

  describe "#inspect" do
    it "includes the description and line_amount" do
      item = described_class.new(full_attrs)

      expect(item.inspect).to include("description=")
      expect(item.inspect).to include("line_amount=")
    end
  end
end
