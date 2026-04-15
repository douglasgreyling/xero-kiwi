# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::Allocation do
  let(:full_attrs) do
    {
      "AllocationID" => "b12335f4-a1e5-4431-aeb4-488e5547558e",
      "Amount"       => "100.00",
      "Date"         => "/Date(1401062400000+0000)/",
      "Invoice"      => { "InvoiceID"     => "87cfa39f-136c-4df9-a70d-bb80d8ddb975",
                          "InvoiceNumber" => "INV-0001" },
      "IsDeleted"    => false
    }
  end

  describe "#initialize" do
    subject(:allocation) { described_class.new(full_attrs) }

    it "maps all scalar attributes" do
      expect(allocation).to have_attributes(
        allocation_id: "b12335f4-a1e5-4431-aeb4-488e5547558e",
        amount:        "100.00",
        is_deleted:    false
      )
    end

    it "parses the date into a UTC Time" do
      expect(allocation.date).to be_a(Time)
      expect(allocation.date.utc_offset).to eq(0)
    end

    it "wraps the invoice as a XeroKiwi::Accounting::Invoice reference" do
      expect(allocation.invoice).to be_a(XeroKiwi::Accounting::Invoice)
      expect(allocation.invoice.invoice_id).to eq("87cfa39f-136c-4df9-a70d-bb80d8ddb975")
      expect(allocation.invoice.invoice_number).to eq("INV-0001")
      expect(allocation.invoice.reference?).to be true
    end

    it "handles nil Invoice gracefully" do
      allocation = described_class.new({ "AllocationID" => "abc" })
      expect(allocation.invoice).to be_nil
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      allocation = described_class.new(full_attrs)
      hash       = allocation.to_h

      expect(hash[:allocation_id]).to eq("b12335f4-a1e5-4431-aeb4-488e5547558e")
      expect(hash.keys).to match_array(described_class::ATTRIBUTES.keys)
    end
  end

  describe "equality" do
    it "considers two allocations equal when they share the same allocation_id" do
      a = described_class.new({ "AllocationID" => "abc", "Amount" => "100" })
      b = described_class.new({ "AllocationID" => "abc", "Amount" => "200" })

      expect(a).to eq(b)
      expect(a).to eql(b)
      expect(a.hash).to eq(b.hash)
    end

    it "considers allocations with different IDs unequal" do
      a = described_class.new({ "AllocationID" => "abc" })
      b = described_class.new({ "AllocationID" => "xyz" })

      expect(a).not_to eq(b)
    end
  end

  describe "#inspect" do
    it "includes the id and amount" do
      allocation = described_class.new(full_attrs)

      expect(allocation.inspect).to include("allocation_id=")
      expect(allocation.inspect).to include("amount=")
    end
  end
end
