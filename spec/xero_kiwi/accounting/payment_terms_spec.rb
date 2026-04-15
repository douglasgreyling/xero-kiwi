# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::PaymentTerms do
  let(:full_attrs) do
    {
      "Bills" => { "Day" => 15, "Type" => "OFCURRENTMONTH" },
      "Sales" => { "Day" => 20, "Type" => "OFFOLLOWINGMONTH" }
    }
  end

  describe ".from_hash" do
    it "returns a PaymentTerms from a hash" do
      terms = described_class.from_hash(full_attrs)

      expect(terms).to be_a(described_class)
      expect(terms.bills).to have_attributes(day: 15, type: "OFCURRENTMONTH")
      expect(terms.sales).to have_attributes(day: 20, type: "OFFOLLOWINGMONTH")
    end

    it "returns nil when given nil" do
      expect(described_class.from_hash(nil)).to be_nil
    end
  end

  describe "#bills and #sales" do
    it "returns XeroKiwi::Accounting::PaymentTerm objects" do
      terms = described_class.new(full_attrs)

      expect(terms.bills).to be_a(XeroKiwi::Accounting::PaymentTerm)
      expect(terms.sales).to be_a(XeroKiwi::Accounting::PaymentTerm)
    end

    it "returns nil for bills/sales when the nested hash is empty" do
      terms = described_class.new("Bills" => {}, "Sales" => {})

      expect(terms.bills).to be_nil
      expect(terms.sales).to be_nil
    end
  end

  describe "#to_h" do
    it "returns nested hashes" do
      terms = described_class.new(full_attrs)

      expect(terms.to_h).to eq(
        bills: { day: 15, type: "OFCURRENTMONTH" },
        sales: { day: 20, type: "OFFOLLOWINGMONTH" }
      )
    end
  end

  describe "equality" do
    it "considers terms with the same bills and sales equal" do
      a = described_class.new(full_attrs)
      b = described_class.new(full_attrs)

      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
    end
  end

  describe XeroKiwi::Accounting::PaymentTerm do
    describe ".from_hash" do
      it "returns a PaymentTerm from a hash" do
        term = described_class.from_hash("Day" => 10, "Type" => "DAYSAFTERBILLDATE")

        expect(term).to have_attributes(day: 10, type: "DAYSAFTERBILLDATE")
      end

      it "returns nil when given nil" do
        expect(described_class.from_hash(nil)).to be_nil
      end

      it "returns nil when given an empty hash" do
        expect(described_class.from_hash({})).to be_nil
      end
    end

    describe "#to_h" do
      it "returns a hash keyed by ruby attribute names" do
        term = described_class.new("Day" => 5, "Type" => "DAYSAFTERBILLMONTH")
        expect(term.to_h).to eq(day: 5, type: "DAYSAFTERBILLMONTH")
      end
    end
  end
end
