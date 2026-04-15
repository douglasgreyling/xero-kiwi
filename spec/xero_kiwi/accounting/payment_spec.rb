# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::Payment do
  let(:full_attrs) do
    {
      "PaymentID"      => "b26fd49a-cbae-470a-a8f8-bcbc119e0379",
      "Date"           => "/Date(1455667200000+0000)/",
      "CurrencyRate"   => 1.000000,
      "Amount"         => 500.00,
      "BankAmount"     => 500.00,
      "Reference"      => "INV-0001",
      "IsReconciled"   => true,
      "Status"         => "AUTHORISED",
      "PaymentType"    => "ACCRECPAYMENT",
      "UpdatedDateUTC" => "/Date(1289572582537+0000)/",
      "BatchPaymentID" => "b54aa50c-794c-461b-89d1-846e1b84d9c0",
      "BatchPayment"   => { "BatchPaymentID" => "b54aa50c-794c-461b-89d1-846e1b84d9c0",
                            "Status"         => "AUTHORISED" },
      "Account"        => { "AccountID" => "ac993f75-035b-433c-82e0-7b7a2d40802c",
                             "Code" => "090", "Name" => "Account Name" },
      "Invoice"        => { "InvoiceID"     => "6a539484-ad93-47a4-a3f3-053fbb7a0606",
                            "InvoiceNumber" => "INV-0001" },
      "CreditNote"     => nil,
      "Prepayment"     => nil,
      "Overpayment"    => nil,
      "HasAccount"     => true
    }
  end

  describe ".from_response" do
    it "parses Payments from the Xero response envelope" do
      payload  = { "Payments" => [full_attrs] }
      payments = described_class.from_response(payload)

      expect(payments).to all(be_a(described_class))
      expect(payments.first.payment_id).to eq("b26fd49a-cbae-470a-a8f8-bcbc119e0379")
    end

    it "returns multiple payments when present" do
      second  = full_attrs.merge("PaymentID" => "abc-123")
      payload = { "Payments" => [full_attrs, second] }

      expect(described_class.from_response(payload).size).to eq(2)
    end

    it "returns an empty array when payload is nil" do
      expect(described_class.from_response(nil)).to eq([])
    end

    it "returns an empty array when Payments key is missing" do
      expect(described_class.from_response({})).to eq([])
    end

    it "returns an empty array when Payments array is empty" do
      expect(described_class.from_response("Payments" => [])).to eq([])
    end
  end

  describe "#initialize" do
    subject(:payment) { described_class.new(full_attrs) }

    it "maps all scalar attributes" do
      expect(payment).to have_attributes(
        payment_id:       "b26fd49a-cbae-470a-a8f8-bcbc119e0379",
        currency_rate:    1.000000,
        amount:           500.00,
        bank_amount:      500.00,
        reference:        "INV-0001",
        is_reconciled:    true,
        status:           "AUTHORISED",
        payment_type:     "ACCRECPAYMENT",
        batch_payment_id: "b54aa50c-794c-461b-89d1-846e1b84d9c0",
        has_account:      true
      )
    end

    it "parses time fields into UTC Time objects" do
      expect(payment.date).to be_a(Time)
      expect(payment.date.utc_offset).to eq(0)
      expect(payment.updated_date_utc).to be_a(Time)
    end

    it "wraps the invoice as a XeroKiwi::Accounting::Invoice reference" do
      expect(payment.invoice).to be_a(XeroKiwi::Accounting::Invoice)
      expect(payment.invoice.invoice_id).to eq("6a539484-ad93-47a4-a3f3-053fbb7a0606")
      expect(payment.invoice.reference?).to be true
    end

    it "wraps credit_note as a reference when present" do
      attrs = full_attrs.merge("CreditNote" => { "CreditNoteID" => "cn-1" })
      p     = described_class.new(attrs)

      expect(p.credit_note).to be_a(XeroKiwi::Accounting::CreditNote)
      expect(p.credit_note.reference?).to be true
    end

    it "wraps prepayment as a reference when present" do
      attrs = full_attrs.merge("Prepayment" => { "PrepaymentID" => "pp-1" })
      p     = described_class.new(attrs)

      expect(p.prepayment).to be_a(XeroKiwi::Accounting::Prepayment)
      expect(p.prepayment.reference?).to be true
    end

    it "wraps overpayment as a reference when present" do
      attrs = full_attrs.merge("Overpayment" => { "OverpaymentID" => "op-1" })
      p     = described_class.new(attrs)

      expect(p.overpayment).to be_a(XeroKiwi::Accounting::Overpayment)
      expect(p.overpayment.reference?).to be true
    end

    it "preserves account and batch_payment as raw hashes" do
      expect(payment.account).to include("AccountID" => "ac993f75-035b-433c-82e0-7b7a2d40802c")
      expect(payment.batch_payment).to include("BatchPaymentID" => "b54aa50c-794c-461b-89d1-846e1b84d9c0")
    end
  end

  describe "#reference?" do
    it "returns false by default" do
      expect(described_class.new(full_attrs).reference?).to be false
    end

    it "returns true when constructed with reference: true" do
      payment = described_class.new(full_attrs, reference: true)
      expect(payment.reference?).to be true
    end

    it "returns false for payments from from_response" do
      payload = { "Payments" => [full_attrs] }
      payment = described_class.from_response(payload).first
      expect(payment.reference?).to be false
    end
  end

  describe "#reconciled?" do
    it "returns true when IsReconciled is true" do
      expect(described_class.new(full_attrs).reconciled?).to be true
    end

    it "returns false when IsReconciled is false" do
      payment = described_class.new(full_attrs.merge("IsReconciled" => false))
      expect(payment.reconciled?).to be false
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      payment = described_class.new(full_attrs)
      hash    = payment.to_h

      expect(hash[:payment_id]).to eq("b26fd49a-cbae-470a-a8f8-bcbc119e0379")
      expect(hash.keys).to match_array(described_class::ATTRIBUTES.keys)
    end
  end

  describe "equality" do
    it "considers two payments equal when they share the same payment_id" do
      a = described_class.new({ "PaymentID" => "abc", "Amount" => 100 })
      b = described_class.new({ "PaymentID" => "abc", "Amount" => 200 })

      expect(a).to eq(b)
      expect(a).to eql(b)
      expect(a.hash).to eq(b.hash)
    end

    it "considers payments with different IDs unequal" do
      a = described_class.new({ "PaymentID" => "abc" })
      b = described_class.new({ "PaymentID" => "xyz" })

      expect(a).not_to eq(b)
    end
  end

  describe "#inspect" do
    it "includes the id, type, status, and amount" do
      payment = described_class.new(full_attrs)

      expect(payment.inspect).to include("payment_id=")
      expect(payment.inspect).to include("payment_type=")
      expect(payment.inspect).to include("status=")
      expect(payment.inspect).to include("amount=")
    end
  end
end
