# frozen_string_literal: true

RSpec.describe XeroKiwi::Query::Order do
  let(:fields) do
    {
      date:           { path: "Date",          type: :date },
      invoice_number: { path: "InvoiceNumber", type: :string },
      status:         { path: "Status",        type: :enum }
    }
  end

  describe ".compile" do
    it "returns nil for nil input" do
      expect(described_class.compile(nil, fields: fields)).to be_nil
    end

    it "passes raw String through unchanged" do
      expect(described_class.compile("Date DESC", fields: fields)).to eq("Date DESC")
    end

    it "raises when given something other than Hash or String" do
      expect { described_class.compile(42, fields: fields) }
        .to raise_error(ArgumentError, /must be a Hash or String/)
    end

    it "renders a single field with direction" do
      expect(described_class.compile({ date: :desc }, fields: fields)).to eq("Date DESC")
    end

    it "joins multiple fields with commas in declaration order" do
      result = described_class.compile(
        { date: :desc, invoice_number: :asc },
        fields: fields
      )

      expect(result).to eq("Date DESC,InvoiceNumber ASC")
    end

    it "uppercases the direction regardless of case" do
      expect(described_class.compile({ status: "asc" }, fields: fields)).to eq("Status ASC")
    end

    it "raises on unknown field keys" do
      expect { described_class.compile({ bogus: :asc }, fields: fields) }
        .to raise_error(ArgumentError, /unknown order field: :bogus/)
    end
  end
end
