# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::Prepayment do
  let(:full_attrs) do
    {
      "PrepaymentID"    => "aea95d78-ea48-456b-9b08-6bc012600072",
      "Type"            => "RECEIVE-PREPAYMENT",
      "Contact"         => { "ContactID" => "c6c7b870-bb4d-489a-921e-2f0ee4192ff9", "Name" => "Mr Contact" },
      "Date"            => "/Date(1222340661707+0000)/",
      "Status"          => "PAID",
      "LineAmountTypes" => "Inclusive",
      "LineItems"       => [{ "Description" => "Consulting", "LineAmount" => "100.00" }],
      "SubTotal"        => "86.96",
      "TotalTax"        => "13.04",
      "Total"           => "100.00",
      "UpdatedDateUTC"  => "/Date(1222340661707+0000)/",
      "CurrencyCode"    => "NZD",
      "CurrencyRate"    => "1.000000",
      "InvoiceNumber"   => "INV-0001",
      "RemainingCredit" => "0.00",
      "Allocations"     => [{ "Amount" => "100.00", "Date" => "/Date(1222340661707+0000)/" }],
      "Payments"        => [],
      "HasAttachments"  => false,
      "FullyPaidOnDate" => "/Date(1222340661707+0000)/"
    }
  end

  describe ".from_response" do
    it "parses Prepayments from the Xero response envelope" do
      payload     = { "Prepayments" => [full_attrs] }
      prepayments = described_class.from_response(payload)

      expect(prepayments).to all(be_a(described_class))
      expect(prepayments.first.prepayment_id).to eq("aea95d78-ea48-456b-9b08-6bc012600072")
    end

    it "returns multiple prepayments when present" do
      second  = full_attrs.merge("PrepaymentID" => "abc-123")
      payload = { "Prepayments" => [full_attrs, second] }

      expect(described_class.from_response(payload).size).to eq(2)
    end

    it "returns an empty array when payload is nil" do
      expect(described_class.from_response(nil)).to eq([])
    end

    it "returns an empty array when Prepayments key is missing" do
      expect(described_class.from_response({})).to eq([])
    end

    it "returns an empty array when Prepayments array is empty" do
      expect(described_class.from_response("Prepayments" => [])).to eq([])
    end
  end

  describe "#initialize" do
    subject(:prepayment) { described_class.new(full_attrs) }

    it "maps all scalar attributes" do
      expect(prepayment).to have_attributes(
        prepayment_id:     "aea95d78-ea48-456b-9b08-6bc012600072",
        type:              "RECEIVE-PREPAYMENT",
        status:            "PAID",
        line_amount_types: "Inclusive",
        sub_total:         "86.96",
        total_tax:         "13.04",
        total:             "100.00",
        currency_code:     "NZD",
        currency_rate:     "1.000000",
        invoice_number:    "INV-0001",
        remaining_credit:  "0.00",
        has_attachments:   false
      )
    end

    it "wraps the contact as a XeroKiwi::Accounting::Contact reference" do
      expect(prepayment.contact).to be_a(XeroKiwi::Accounting::Contact)
      expect(prepayment.contact.contact_id).to eq("c6c7b870-bb4d-489a-921e-2f0ee4192ff9")
      expect(prepayment.contact.name).to eq("Mr Contact")
      expect(prepayment.contact.reference?).to be true
    end

    it "parses time fields into UTC Time objects" do
      expect(prepayment.date).to be_a(Time)
      expect(prepayment.date.utc_offset).to eq(0)
      expect(prepayment.updated_date_utc).to be_a(Time)
      expect(prepayment.fully_paid_on_date).to be_a(Time)
    end

    it "wraps line_items as XeroKiwi::Accounting::LineItem objects" do
      expect(prepayment.line_items).to all(be_a(XeroKiwi::Accounting::LineItem))
      expect(prepayment.line_items.first.description).to eq("Consulting")
    end

    it "wraps allocations as XeroKiwi::Accounting::Allocation objects" do
      expect(prepayment.allocations).to all(be_a(XeroKiwi::Accounting::Allocation))
      expect(prepayment.allocations.first.amount).to eq("100.00")
    end

    it "defaults collection attributes to empty arrays when absent" do
      prepayment = described_class.new({ "PrepaymentID" => "abc" })

      expect(prepayment).to have_attributes(
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
      prepayment = described_class.new(full_attrs, reference: true)
      expect(prepayment.reference?).to be true
    end
  end

  describe "predicates" do
    it "receive? returns true for RECEIVE-PREPAYMENT" do
      expect(described_class.new(full_attrs).receive?).to be true
    end

    it "spend? returns true for SPEND-PREPAYMENT" do
      prepayment = described_class.new(full_attrs.merge("Type" => "SPEND-PREPAYMENT"))
      expect(prepayment.spend?).to be true
    end

    it "receive? returns false for SPEND-PREPAYMENT" do
      prepayment = described_class.new(full_attrs.merge("Type" => "SPEND-PREPAYMENT"))
      expect(prepayment.receive?).to be false
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      prepayment = described_class.new(full_attrs)
      hash       = prepayment.to_h

      expect(hash[:prepayment_id]).to eq("aea95d78-ea48-456b-9b08-6bc012600072")
      expect(hash.keys).to match_array(described_class.attributes.keys)
    end
  end

  describe "equality" do
    it "considers two prepayments equal when they share the same prepayment_id" do
      a = described_class.new({ "PrepaymentID" => "abc", "Type" => "RECEIVE-PREPAYMENT" })
      b = described_class.new({ "PrepaymentID" => "abc", "Type" => "SPEND-PREPAYMENT" })

      expect(a).to eq(b)
      expect(a).to eql(b)
      expect(a.hash).to eq(b.hash)
    end

    it "considers prepayments with different IDs unequal" do
      a = described_class.new({ "PrepaymentID" => "abc" })
      b = described_class.new({ "PrepaymentID" => "xyz" })

      expect(a).not_to eq(b)
    end
  end

  describe "#inspect" do
    it "includes the id, type, status, and total" do
      prepayment = described_class.new(full_attrs)

      expect(prepayment.inspect).to include("prepayment_id=")
      expect(prepayment.inspect).to include("type=")
      expect(prepayment.inspect).to include("status=")
      expect(prepayment.inspect).to include("total=")
    end
  end
end
