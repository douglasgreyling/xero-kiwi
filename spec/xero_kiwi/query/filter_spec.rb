# frozen_string_literal: true

RSpec.describe XeroKiwi::Query::Filter do
  let(:fields) do
    {
      invoice_id:      { path: "InvoiceID",      type: :guid },
      invoice_number:  { path: "InvoiceNumber",  type: :string },
      status:          { path: "Status",         type: :enum },
      amount:          { path: "Amount",         type: :decimal },
      sent_to_contact: { path: "SentToContact",  type: :bool },
      date:            { path: "Date",           type: :date },
      contact:         {
        path:   "Contact",
        type:   :nested,
        fields: {
          contact_id: { path: "ContactID", type: :guid },
          name:       { path: "Name",      type: :string }
        }
      }
    }
  end

  describe ".compile" do
    it "returns nil for nil input" do
      expect(described_class.compile(nil, fields: fields)).to be_nil
    end

    it "passes a raw String through unchanged" do
      raw = 'Status=="AUTHORISED" || Status=="DRAFT"'
      expect(described_class.compile(raw, fields: fields)).to eq(raw)
    end

    it "raises when given something other than Hash or String" do
      expect { described_class.compile(42, fields: fields) }
        .to raise_error(ArgumentError, /must be a Hash or String/)
    end

    it "compiles a single equality pair" do
      result = described_class.compile({ status: "AUTHORISED" }, fields: fields)

      expect(result).to eq('Status=="AUTHORISED"')
    end

    it "joins multiple pairs with &&" do
      result = described_class.compile(
        { status: "AUTHORISED", invoice_number: "INV-001" },
        fields: fields
      )

      expect(result).to eq('Status=="AUTHORISED"&&InvoiceNumber=="INV-001"')
    end

    it "raises on unknown field keys" do
      expect { described_class.compile({ bogus: "x" }, fields: fields) }
        .to raise_error(ArgumentError, /unknown filter field: :bogus/)
    end

    describe "literal formatting" do
      it "wraps :guid values in Guid(\"...\")" do
        result = described_class.compile({ invoice_id: "abc-123" }, fields: fields)

        expect(result).to eq('InvoiceID==Guid("abc-123")')
      end

      it "escapes double quotes inside :string values" do
        result = described_class.compile({ invoice_number: 'he said "hi"' }, fields: fields)

        expect(result).to eq('InvoiceNumber=="he said \\"hi\\""')
      end

      it "renders :bool as true/false literal" do
        result = described_class.compile({ sent_to_contact: true }, fields: fields)

        expect(result).to eq("SentToContact==true")
      end

      it "renders :decimal as a bare number" do
        result = described_class.compile({ amount: 99.5 }, fields: fields)

        expect(result).to eq("Amount==99.5")
      end

      it "renders :date as DateTime(y,m,d) in UTC" do
        result = described_class.compile({ date: Date.new(2026, 3, 1) }, fields: fields)

        expect(result).to eq("Date==DateTime(2026,3,1)")
      end

      it "coerces Time to UTC before rendering :date" do
        t      = Time.new(2026, 3, 1, 23, 0, 0, "+10:00") # 13:00 UTC, same day
        result = described_class.compile({ date: t }, fields: fields)

        expect(result).to eq("Date==DateTime(2026,3,1)")
      end
    end

    describe "Array values (IN)" do
      it "expands to an OR expression over the field" do
        result = described_class.compile({ status: %w[AUTHORISED DRAFT] }, fields: fields)

        expect(result).to eq('(Status=="AUTHORISED"||Status=="DRAFT")')
      end
    end

    describe "Range values" do
      it "compiles a date range as >= lo && <= hi" do
        range = Date.new(2026, 1, 1)..Date.new(2026, 3, 1)

        result = described_class.compile({ date: range }, fields: fields)

        expect(result).to eq("Date>=DateTime(2026,1,1)&&Date<=DateTime(2026,3,1)")
      end
    end

    describe "nested Hash values" do
      it "compiles a nested filter with a dotted prefix" do
        result = described_class.compile(
          { contact: { contact_id: "c-1" } },
          fields: fields
        )

        expect(result).to eq('Contact.ContactID==Guid("c-1")')
      end

      it "supports multiple nested pairs joined with &&" do
        result = described_class.compile(
          { contact: { contact_id: "c-1", name: "Acme" } },
          fields: fields
        )

        expect(result).to eq('Contact.ContactID==Guid("c-1")&&Contact.Name=="Acme"')
      end

      it "raises when a Hash value targets a non-nested field" do
        expect do
          described_class.compile({ status: { foo: "bar" } }, fields: fields)
        end.to raise_error(ArgumentError, /not a nested filter field/)
      end
    end

    describe "combinations" do
      it "mixes scalar, array, range, and nested in one call" do
        result = described_class.compile(
          {
            status:  %w[AUTHORISED DRAFT],
            date:    Date.new(2026, 1, 1)..Date.new(2026, 3, 1),
            contact: { contact_id: "c-1" }
          },
          fields: fields
        )

        expect(result).to eq(
          '(Status=="AUTHORISED"||Status=="DRAFT")' \
          "&&Date>=DateTime(2026,1,1)&&Date<=DateTime(2026,3,1)" \
          '&&Contact.ContactID==Guid("c-1")'
        )
      end
    end
  end
end
