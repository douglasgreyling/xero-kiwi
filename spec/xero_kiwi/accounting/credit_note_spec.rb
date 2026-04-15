# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::CreditNote do
  let(:full_attrs) do
    {
      "CreditNoteID"     => "aea95d78-ea48-456b-9b08-6bc012600072",
      "CreditNoteNumber" => "CN-0002",
      "Type"             => "ACCRECCREDIT",
      "Contact"          => { "ContactID" => "c6c7b870-bb4d-489a-921e-2f0ee4192ff9",
                              "Name"      => "Test Apply Credit Note" },
      "Date"             => "/Date(1481846400000+0000)/",
      "Status"           => "PAID",
      "LineAmountTypes"  => "Inclusive",
      "LineItems"        => [{ "Description" => "DVD drive refund", "LineAmount" => 199.00 }],
      "SubTotal"         => 86.96,
      "TotalTax"         => 13.04,
      "Total"            => 100.00,
      "CISDeduction"     => nil,
      "UpdatedDateUTC"   => "/Date(1290168061547+0000)/",
      "CurrencyCode"     => "NZD",
      "CurrencyRate"     => 1.000000,
      "FullyPaidOnDate"  => "/Date(1481846400000+0000)/",
      "Reference"        => "REF-001",
      "SentToContact"    => true,
      "RemainingCredit"  => 0.00,
      "Allocations"      => [{ "AllocationID" => "b12335f4", "Amount" => 100.00 }],
      "BrandingThemeID"  => "dfe23d27-a3a6-4ef3-a5ca-b9e02b142dde",
      "HasAttachments"   => false
    }
  end

  describe ".from_response" do
    it "parses CreditNotes from the Xero response envelope" do
      payload      = { "CreditNotes" => [full_attrs] }
      credit_notes = described_class.from_response(payload)

      expect(credit_notes).to all(be_a(described_class))
      expect(credit_notes.first.credit_note_id).to eq("aea95d78-ea48-456b-9b08-6bc012600072")
    end

    it "returns multiple credit notes when present" do
      second  = full_attrs.merge("CreditNoteID" => "abc-123")
      payload = { "CreditNotes" => [full_attrs, second] }

      expect(described_class.from_response(payload).size).to eq(2)
    end

    it "returns an empty array when payload is nil" do
      expect(described_class.from_response(nil)).to eq([])
    end

    it "returns an empty array when CreditNotes key is missing" do
      expect(described_class.from_response({})).to eq([])
    end

    it "returns an empty array when CreditNotes array is empty" do
      expect(described_class.from_response("CreditNotes" => [])).to eq([])
    end
  end

  describe "#initialize" do
    subject(:credit_note) { described_class.new(full_attrs) }

    it "maps all scalar attributes" do
      expect(credit_note).to have_attributes(
        credit_note_id:     "aea95d78-ea48-456b-9b08-6bc012600072",
        credit_note_number: "CN-0002",
        type:               "ACCRECCREDIT",
        status:             "PAID",
        line_amount_types:  "Inclusive",
        sub_total:          86.96,
        total_tax:          13.04,
        total:              100.00,
        currency_code:      "NZD",
        currency_rate:      1.000000,
        reference:          "REF-001",
        sent_to_contact:    true,
        remaining_credit:   0.00,
        branding_theme_id:  "dfe23d27-a3a6-4ef3-a5ca-b9e02b142dde",
        has_attachments:    false
      )
    end

    it "wraps the contact as a XeroKiwi::Accounting::Contact reference" do
      expect(credit_note.contact).to be_a(XeroKiwi::Accounting::Contact)
      expect(credit_note.contact.contact_id).to eq("c6c7b870-bb4d-489a-921e-2f0ee4192ff9")
      expect(credit_note.contact.reference?).to be true
    end

    it "parses time fields into UTC Time objects" do
      expect(credit_note.date).to be_a(Time)
      expect(credit_note.date.utc_offset).to eq(0)
      expect(credit_note.updated_date_utc).to be_a(Time)
      expect(credit_note.fully_paid_on_date).to be_a(Time)
    end

    it "wraps line_items as XeroKiwi::Accounting::LineItem objects" do
      expect(credit_note.line_items).to all(be_a(XeroKiwi::Accounting::LineItem))
      expect(credit_note.line_items.first.description).to eq("DVD drive refund")
    end

    it "wraps allocations as XeroKiwi::Accounting::Allocation objects" do
      expect(credit_note.allocations).to all(be_a(XeroKiwi::Accounting::Allocation))
      expect(credit_note.allocations.first.amount).to eq(100.00)
    end

    it "defaults collection attributes to empty arrays when absent" do
      cn = described_class.new({ "CreditNoteID" => "abc" })

      expect(cn).to have_attributes(
        line_items:  [],
        allocations: []
      )
    end
  end

  describe "predicates" do
    it "reference? returns false by default" do
      expect(described_class.new(full_attrs).reference?).to be false
    end

    it "reference? returns true when constructed with reference: true" do
      cn = described_class.new(full_attrs, reference: true)
      expect(cn.reference?).to be true
    end

    it "accounts_receivable? returns true for ACCRECCREDIT" do
      expect(described_class.new(full_attrs).accounts_receivable?).to be true
    end

    it "accounts_payable? returns true for ACCPAYCREDIT" do
      cn = described_class.new(full_attrs.merge("Type" => "ACCPAYCREDIT"))
      expect(cn.accounts_payable?).to be true
    end

    it "accounts_receivable? returns false for ACCPAYCREDIT" do
      cn = described_class.new(full_attrs.merge("Type" => "ACCPAYCREDIT"))
      expect(cn.accounts_receivable?).to be false
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      cn   = described_class.new(full_attrs)
      hash = cn.to_h

      expect(hash[:credit_note_id]).to eq("aea95d78-ea48-456b-9b08-6bc012600072")
      expect(hash.keys).to match_array(described_class::ATTRIBUTES.keys)
    end
  end

  describe "equality" do
    it "considers two credit notes equal when they share the same credit_note_id" do
      a = described_class.new({ "CreditNoteID" => "abc", "Type" => "ACCRECCREDIT" })
      b = described_class.new({ "CreditNoteID" => "abc", "Type" => "ACCPAYCREDIT" })

      expect(a).to eq(b)
      expect(a).to eql(b)
      expect(a.hash).to eq(b.hash)
    end

    it "considers credit notes with different IDs unequal" do
      a = described_class.new({ "CreditNoteID" => "abc" })
      b = described_class.new({ "CreditNoteID" => "xyz" })

      expect(a).not_to eq(b)
    end
  end

  describe "#inspect" do
    it "includes the id, type, status, and total" do
      cn = described_class.new(full_attrs)

      expect(cn.inspect).to include("credit_note_id=")
      expect(cn.inspect).to include("type=")
      expect(cn.inspect).to include("status=")
      expect(cn.inspect).to include("total=")
    end
  end
end
