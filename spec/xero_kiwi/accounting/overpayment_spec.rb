# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::Overpayment do
  let(:full_attrs) do
    {
      "OverpaymentID"   => "aea95d78-ea48-456b-9b08-6bc012600072",
      "Type"            => "RECEIVE-OVERPAYMENT",
      "Contact"         => { "ContactID" => "c6c7b870-bb4d-489a-921e-2f0ee4192ff9", "Name" => "Mr Contact" },
      "Date"            => "/Date(1401062400000+0000)/",
      "Status"          => "PAID",
      "LineAmountTypes" => "Inclusive",
      "LineItems"       => [{ "Description" => "Overpayment", "LineAmount" => "100.00" }],
      "SubTotal"        => "86.96",
      "TotalTax"        => "13.04",
      "Total"           => "100.00",
      "UpdatedDateUTC"  => "2015-03-29T23:43:01.097",
      "CurrencyCode"    => "NZD",
      "CurrencyRate"    => "1.000000",
      "RemainingCredit" => "0.00",
      "Allocations"     => [{ "AllocationID" => "b12335f4", "Amount" => "100.00" }],
      "Payments"        => [],
      "HasAttachments"  => false,
      "Reference"       => "Overpayment Reference"
    }
  end

  describe ".from_response" do
    it "parses Overpayments from the Xero response envelope" do
      payload      = { "Overpayments" => [full_attrs] }
      overpayments = described_class.from_response(payload)

      expect(overpayments).to all(be_a(described_class))
      expect(overpayments.first.overpayment_id).to eq("aea95d78-ea48-456b-9b08-6bc012600072")
    end

    it "returns multiple overpayments when present" do
      second  = full_attrs.merge("OverpaymentID" => "abc-123")
      payload = { "Overpayments" => [full_attrs, second] }

      expect(described_class.from_response(payload).size).to eq(2)
    end

    it "returns an empty array when payload is nil" do
      expect(described_class.from_response(nil)).to eq([])
    end

    it "returns an empty array when Overpayments key is missing" do
      expect(described_class.from_response({})).to eq([])
    end

    it "returns an empty array when Overpayments array is empty" do
      expect(described_class.from_response("Overpayments" => [])).to eq([])
    end
  end

  describe "#initialize" do
    subject(:overpayment) { described_class.new(full_attrs) }

    it "maps all scalar attributes" do
      expect(overpayment).to have_attributes(
        overpayment_id:    "aea95d78-ea48-456b-9b08-6bc012600072",
        type:              "RECEIVE-OVERPAYMENT",
        status:            "PAID",
        line_amount_types: "Inclusive",
        sub_total:         "86.96",
        total_tax:         "13.04",
        total:             "100.00",
        currency_code:     "NZD",
        currency_rate:     "1.000000",
        remaining_credit:  "0.00",
        has_attachments:   false,
        reference:         "Overpayment Reference"
      )
    end

    it "wraps the contact as a XeroKiwi::Accounting::Contact reference" do
      expect(overpayment.contact).to be_a(XeroKiwi::Accounting::Contact)
      expect(overpayment.contact.contact_id).to eq("c6c7b870-bb4d-489a-921e-2f0ee4192ff9")
      expect(overpayment.contact.name).to eq("Mr Contact")
      expect(overpayment.contact.reference?).to be true
    end

    it "parses time fields into UTC Time objects" do
      expect(overpayment.date).to be_a(Time)
      expect(overpayment.date.utc_offset).to eq(0)
      expect(overpayment.updated_date_utc).to be_a(Time)
    end

    it "wraps line_items as XeroKiwi::Accounting::LineItem objects" do
      expect(overpayment.line_items).to all(be_a(XeroKiwi::Accounting::LineItem))
      expect(overpayment.line_items.first.description).to eq("Overpayment")
    end

    it "wraps allocations as XeroKiwi::Accounting::Allocation objects" do
      expect(overpayment.allocations).to all(be_a(XeroKiwi::Accounting::Allocation))
      expect(overpayment.allocations.first.amount).to eq("100.00")
    end

    it "defaults collection attributes to empty arrays when absent" do
      op = described_class.new({ "OverpaymentID" => "abc" })

      expect(op).to have_attributes(
        line_items:  [],
        allocations: [],
        payments:    []
      )
    end
  end

  describe "#reference?" do
    it "returns false by default" do
      expect(described_class.new(full_attrs).reference?).to be false
    end

    it "returns true when constructed with reference: true" do
      op = described_class.new(full_attrs, reference: true)
      expect(op.reference?).to be true
    end
  end

  describe "predicates" do
    it "receive? returns true for RECEIVE-OVERPAYMENT" do
      expect(described_class.new(full_attrs).receive?).to be true
    end

    it "spend? returns true for SPEND-OVERPAYMENT" do
      op = described_class.new(full_attrs.merge("Type" => "SPEND-OVERPAYMENT"))
      expect(op.spend?).to be true
    end

    it "receive? returns false for SPEND-OVERPAYMENT" do
      op = described_class.new(full_attrs.merge("Type" => "SPEND-OVERPAYMENT"))
      expect(op.receive?).to be false
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      op   = described_class.new(full_attrs)
      hash = op.to_h

      expect(hash[:overpayment_id]).to eq("aea95d78-ea48-456b-9b08-6bc012600072")
      expect(hash.keys).to match_array(described_class::ATTRIBUTES.keys)
    end
  end

  describe "equality" do
    it "considers two overpayments equal when they share the same overpayment_id" do
      a = described_class.new({ "OverpaymentID" => "abc", "Type" => "RECEIVE-OVERPAYMENT" })
      b = described_class.new({ "OverpaymentID" => "abc", "Type" => "SPEND-OVERPAYMENT" })

      expect(a).to eq(b)
      expect(a).to eql(b)
      expect(a.hash).to eq(b.hash)
    end

    it "considers overpayments with different IDs unequal" do
      a = described_class.new({ "OverpaymentID" => "abc" })
      b = described_class.new({ "OverpaymentID" => "xyz" })

      expect(a).not_to eq(b)
    end
  end

  describe "#inspect" do
    it "includes the id, type, status, and total" do
      op = described_class.new(full_attrs)

      expect(op.inspect).to include("overpayment_id=")
      expect(op.inspect).to include("type=")
      expect(op.inspect).to include("status=")
      expect(op.inspect).to include("total=")
    end
  end
end
