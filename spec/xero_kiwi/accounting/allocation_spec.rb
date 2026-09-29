# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::Allocation do
  # Deliberately keyed "AppliedAmount", which is what Xero's XML sends. JSON
  # sends "Amount", and the reader resolves either — see the class. The JSON
  # side is asserted against a real recording in recorded_responses_spec.rb
  # rather than here, since a fabricated payload can only confirm whatever
  # shape it was written in.
  let(:full_attrs) do
    {
      "AllocationID"  => "b12335f4-a1e5-4431-aeb4-488e5547558e",
      "AppliedAmount" => 553.15,
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
        applied_amount: BigDecimal("553.15"),
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

  # Xero sends the allocated value under "Amount" in JSON and
  # "AppliedAmount" in XML. This client is JSON-only, but the distinction has
  # been got wrong twice in opposite directions — each time producing a
  # silent nil that an importer turned into a zero — so both keys are read
  # and both readers resolve.
  describe "the allocated value" do
    let(:json_shaped) { { "AllocationID" => "abc", "Amount" => 521.23 } }
    let(:xml_shaped)  { { "AllocationID" => "abc", "AppliedAmount" => 553.15 } }

    it "reads Xero's JSON key", :aggregate_failures do
      allocation = described_class.new(json_shaped)

      expect(allocation.amount).to eq(521.23)
      expect(allocation.applied_amount).to eq(521.23)
    end

    it "reads Xero's XML key", :aggregate_failures do
      allocation = described_class.new(xml_shaped)

      expect(allocation.applied_amount).to eq(BigDecimal("553.15"))
      expect(allocation.amount).to eq(BigDecimal("553.15"))
    end

    it "is nil only when neither key is present", :aggregate_failures do
      allocation = described_class.new({ "AllocationID" => "abc" })

      expect(allocation.amount).to be_nil
      expect(allocation.applied_amount).to be_nil
    end

    # The failure mode both regressions shared: a nil that an importer
    # coerces to 0.0 and stores, with nothing raising anywhere.
    it "never leaves one reader nil while the other has a value" do
      [json_shaped, xml_shaped].each do |attrs|
        allocation = described_class.new(attrs)
        expect([allocation.amount, allocation.applied_amount]).to all(be_truthy)
      end
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names", :aggregate_failures do
      hash = described_class.new(full_attrs).to_h

      expect(hash[:allocation_id]).to eq("b12335f4-a1e5-4431-aeb4-488e5547558e")
      expect(hash[:applied_amount]).to eq(BigDecimal("553.15"))
      expect(hash.keys).to match_array(described_class.attributes.keys)
    end

    # Both keys are declared attributes and both readers resolve, so the
    # projection reports the value twice. `raw` is where you look to see
    # which key Xero actually sent.
    it "reports the allocated value under both keys" do
      expect(described_class.new(full_attrs).to_h).to include(amount: BigDecimal("553.15"), applied_amount: BigDecimal("553.15"))
    end
  end

  describe "equality" do
    it "considers two allocations equal when they share the same allocation_id", :aggregate_failures do
      a = described_class.new({ "AllocationID" => "abc", "AppliedAmount" => 100 })
      b = described_class.new({ "AllocationID" => "abc", "AppliedAmount" => 200 })

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
