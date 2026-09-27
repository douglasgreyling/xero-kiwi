# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::Allocation do
  # Shaped after a real allocation embedded in a CreditNote response.
  # Responses carry "AppliedAmount"; "Amount" belongs to the allocation
  # *request* body, which this reader-only gem never sends. The previous
  # version of this spec used a fabricated "Amount" payload and so agreed
  # with the bug instead of catching it.
  let(:full_attrs) do
    {
      "AllocationID"  => "b12335f4-a1e5-4431-aeb4-488e5547558e",
      "AppliedAmount" => "553.15",
      "Date"          => "/Date(1401062400000+0000)/",
      "Invoice"       => { "InvoiceID"     => "87cfa39f-136c-4df9-a70d-bb80d8ddb975",
                           "InvoiceNumber" => "INV-0040" },
      "IsDeleted"     => false
    }
  end

  describe "#initialize" do
    subject(:allocation) { described_class.new(full_attrs) }

    it "maps all scalar attributes" do
      expect(allocation).to have_attributes(
        allocation_id:  "b12335f4-a1e5-4431-aeb4-488e5547558e",
        applied_amount: "553.15",
        is_deleted:     false
      )
    end

    it "parses the date into a UTC Time", :aggregate_failures do
      expect(allocation.date).to be_a(Time)
      expect(allocation.date.utc_offset).to eq(0)
    end

    it "wraps the invoice as a XeroKiwi::Accounting::Invoice reference", :aggregate_failures do
      expect(allocation.invoice).to be_a(XeroKiwi::Accounting::Invoice)
      expect(allocation.invoice.invoice_id).to eq("87cfa39f-136c-4df9-a70d-bb80d8ddb975")
      expect(allocation.invoice.invoice_number).to eq("INV-0040")
      expect(allocation.invoice.reference?).to be true
    end

    it "handles nil Invoice gracefully" do
      expect(described_class.new({ "AllocationID" => "abc" }).invoice).to be_nil
    end
  end

  describe "#amount" do
    it "aliases applied_amount" do
      expect(described_class.new(full_attrs).amount).to eq("553.15")
    end

    # The bug this replaced: mapping `amount` to "Amount" meant every
    # allocation the gem could produce returned nil, so
    # `allocations.map(&:amount)` yielded an array of nils rather than
    # raising. A caller importing that would have written zeroes.
    it "is not nil for a response-shaped payload" do
      expect(described_class.new(full_attrs).amount).not_to be_nil
    end

    # Documents the direction: "Amount" is the request key, so a payload
    # carrying only it is not something Xero ever returns here.
    it "is nil when only the request-shaped Amount key is present" do
      expect(described_class.new({ "AllocationID" => "abc", "Amount" => "100.00" }).amount).to be_nil
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names", :aggregate_failures do
      hash = described_class.new(full_attrs).to_h

      expect(hash[:allocation_id]).to eq("b12335f4-a1e5-4431-aeb4-488e5547558e")
      expect(hash[:applied_amount]).to eq("553.15")
      expect(hash.keys).to match_array(described_class.attributes.keys)
    end

    # amount is a plain reader, not a declared attribute, so it stays out of
    # the projection — one value, one key.
    it "does not carry an amount key" do
      expect(described_class.new(full_attrs).to_h).not_to have_key(:amount)
    end
  end

  describe "equality" do
    it "considers two allocations equal when they share the same allocation_id", :aggregate_failures do
      a = described_class.new({ "AllocationID" => "abc", "AppliedAmount" => "100" })
      b = described_class.new({ "AllocationID" => "abc", "AppliedAmount" => "200" })

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
    it "includes the id and applied amount", :aggregate_failures do
      inspected = described_class.new(full_attrs).inspect

      expect(inspected).to include("allocation_id=")
      expect(inspected).to include("applied_amount=")
    end
  end
end
