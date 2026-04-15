# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::Invoice do
  let(:full_attrs) do
    {
      "InvoiceID"           => "243216c5-369e-4056-ac67-05388f86dc81",
      "InvoiceNumber"       => "OIT00546",
      "Type"                => "ACCREC",
      "Contact"             => { "ContactID" => "025867f1-d741-4d6b-b1af-9ac774b59ba7",
                                 "Name"      => "City Agency" },
      "Date"                => "/Date(1518685950940+0000)/",
      "DueDate"             => "/Date(1518685950940+0000)/",
      "Status"              => "AUTHORISED",
      "LineAmountTypes"     => "Exclusive",
      "LineItems"           => [{ "Description" => "Onsite project management",
                                 "Quantity" => "1.0000", "UnitAmount" => "1800.00",
                                 "LineAmount" => "1800.00", "AccountCode" => "200" }],
      "SubTotal"            => "1800.00",
      "TotalTax"            => "225.00",
      "Total"               => "2025.00",
      "TotalDiscount"       => "0.00",
      "UpdatedDateUTC"      => "/Date(1518685950940+0000)/",
      "CurrencyCode"        => "NZD",
      "CurrencyRate"        => 1.000000,
      "Reference"           => "Ref:SMITHK",
      "BrandingThemeID"     => "3b148ee0-adfa-442c-a98b-9059a73e8ef5",
      "Url"                 => "http://www.example.com",
      "SentToContact"       => false,
      "ExpectedPaymentDate" => "/Date(1518685950940+0000)/",
      "PlannedPaymentDate"  => nil,
      "HasAttachments"      => false,
      "RepeatingInvoiceID"  => nil,
      "Payments"            => [{ "PaymentID" => "0d666415", "Amount" => "1000.00" }],
      "CreditNotes"         => [],
      "Prepayments"         => [],
      "Overpayments"        => [],
      "AmountDue"           => "1025.00",
      "AmountPaid"          => "1000.00",
      "AmountCredited"      => "0.00",
      "CISDeduction"        => nil,
      "FullyPaidOnDate"     => nil,
      "InvoiceAddresses"    => []
    }
  end

  describe ".from_response" do
    it "parses Invoices from the Xero response envelope" do
      payload  = { "Invoices" => [full_attrs] }
      invoices = described_class.from_response(payload)

      expect(invoices).to all(be_a(described_class))
      expect(invoices.first.invoice_id).to eq("243216c5-369e-4056-ac67-05388f86dc81")
    end

    it "returns multiple invoices when present" do
      second  = full_attrs.merge("InvoiceID" => "abc-123")
      payload = { "Invoices" => [full_attrs, second] }

      expect(described_class.from_response(payload).size).to eq(2)
    end

    it "returns an empty array when payload is nil" do
      expect(described_class.from_response(nil)).to eq([])
    end

    it "returns an empty array when Invoices key is missing" do
      expect(described_class.from_response({})).to eq([])
    end

    it "returns an empty array when Invoices array is empty" do
      expect(described_class.from_response("Invoices" => [])).to eq([])
    end
  end

  describe "#initialize" do
    subject(:invoice) { described_class.new(full_attrs) }

    it "maps all scalar attributes" do
      expect(invoice).to have_attributes(
        invoice_id:        "243216c5-369e-4056-ac67-05388f86dc81",
        invoice_number:    "OIT00546",
        type:              "ACCREC",
        status:            "AUTHORISED",
        line_amount_types: "Exclusive",
        sub_total:         "1800.00",
        total_tax:         "225.00",
        total:             "2025.00",
        total_discount:    "0.00",
        currency_code:     "NZD",
        currency_rate:     1.000000,
        reference:         "Ref:SMITHK",
        branding_theme_id: "3b148ee0-adfa-442c-a98b-9059a73e8ef5",
        url:               "http://www.example.com",
        sent_to_contact:   false,
        has_attachments:   false,
        amount_due:        "1025.00",
        amount_paid:       "1000.00",
        amount_credited:   "0.00"
      )
    end

    it "wraps the contact as a XeroKiwi::Accounting::Contact reference" do
      expect(invoice.contact).to be_a(XeroKiwi::Accounting::Contact)
      expect(invoice.contact.contact_id).to eq("025867f1-d741-4d6b-b1af-9ac774b59ba7")
      expect(invoice.contact.reference?).to be true
    end

    it "parses time fields into UTC Time objects" do
      expect(invoice.date).to be_a(Time)
      expect(invoice.date.utc_offset).to eq(0)
      expect(invoice.due_date).to be_a(Time)
      expect(invoice.updated_date_utc).to be_a(Time)
      expect(invoice.expected_payment_date).to be_a(Time)
    end

    it "wraps line_items as XeroKiwi::Accounting::LineItem objects" do
      expect(invoice.line_items).to all(be_a(XeroKiwi::Accounting::LineItem))
      expect(invoice.line_items.first.description).to eq("Onsite project management")
    end

    it "wraps payments as XeroKiwi::Accounting::Payment references" do
      expect(invoice.payments).to all(be_a(XeroKiwi::Accounting::Payment))
      expect(invoice.payments.first.payment_id).to eq("0d666415")
      expect(invoice.payments.first.reference?).to be true
    end

    it "preserves credit_notes, prepayments, overpayments as raw data" do
      expect(invoice.credit_notes).to eq([])
      expect(invoice.prepayments).to eq([])
      expect(invoice.overpayments).to eq([])
    end

    it "defaults collection attributes to empty arrays when absent" do
      inv = described_class.new({ "InvoiceID" => "abc" })

      expect(inv).to have_attributes(
        line_items:        [],
        payments:          [],
        credit_notes:      [],
        prepayments:       [],
        overpayments:      [],
        invoice_addresses: []
      )
    end
  end

  describe "#reference?" do
    it "returns false by default" do
      inv = described_class.new({ "InvoiceID" => "abc" })
      expect(inv.reference?).to be false
    end

    it "returns true when constructed with reference: true" do
      inv = described_class.new({ "InvoiceID" => "abc" }, reference: true)
      expect(inv.reference?).to be true
    end

    it "returns false for invoices from from_response" do
      payload = { "Invoices" => [full_attrs] }
      inv     = described_class.from_response(payload).first
      expect(inv.reference?).to be false
    end
  end

  describe "predicates" do
    it "accounts_receivable? returns true for ACCREC" do
      expect(described_class.new(full_attrs).accounts_receivable?).to be true
    end

    it "accounts_payable? returns true for ACCPAY" do
      inv = described_class.new(full_attrs.merge("Type" => "ACCPAY"))
      expect(inv.accounts_payable?).to be true
    end

    it "accounts_receivable? returns false for ACCPAY" do
      inv = described_class.new(full_attrs.merge("Type" => "ACCPAY"))
      expect(inv.accounts_receivable?).to be false
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      inv  = described_class.new(full_attrs)
      hash = inv.to_h

      expect(hash[:invoice_id]).to eq("243216c5-369e-4056-ac67-05388f86dc81")
      expect(hash.keys).to match_array(described_class::ATTRIBUTES.keys)
    end
  end

  describe "equality" do
    it "considers two invoices equal when they share the same invoice_id" do
      a = described_class.new({ "InvoiceID" => "abc", "InvoiceNumber" => "INV-001" })
      b = described_class.new({ "InvoiceID" => "abc", "InvoiceNumber" => "INV-002" })

      expect(a).to eq(b)
      expect(a).to eql(b)
      expect(a.hash).to eq(b.hash)
    end

    it "considers invoices with different IDs unequal" do
      a = described_class.new({ "InvoiceID" => "abc" })
      b = described_class.new({ "InvoiceID" => "xyz" })

      expect(a).not_to eq(b)
    end
  end

  describe "#inspect" do
    it "includes the id, number, type, status, and total" do
      inv = described_class.new(full_attrs)

      expect(inv.inspect).to include("invoice_id=")
      expect(inv.inspect).to include("invoice_number=")
      expect(inv.inspect).to include("type=")
      expect(inv.inspect).to include("status=")
      expect(inv.inspect).to include("total=")
    end
  end
end
