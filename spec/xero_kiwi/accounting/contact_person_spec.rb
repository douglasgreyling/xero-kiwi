# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::ContactPerson do
  let(:full_attrs) do
    {
      "FirstName"       => "John",
      "LastName"        => "Smith",
      "EmailAddress"    => "john.smith@24locks.com",
      "IncludeInEmails" => true
    }
  end

  describe "#initialize" do
    it "maps all attributes" do
      person = described_class.new(full_attrs)

      expect(person).to have_attributes(
        first_name:        "John",
        last_name:         "Smith",
        email_address:     "john.smith@24locks.com",
        include_in_emails: true
      )
    end
  end

  describe "#include_in_emails?" do
    it "returns true when IncludeInEmails is true" do
      expect(described_class.new(full_attrs).include_in_emails?).to be true
    end

    it "returns false when IncludeInEmails is false" do
      person = described_class.new(full_attrs.merge("IncludeInEmails" => false))
      expect(person.include_in_emails?).to be false
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      person = described_class.new(full_attrs)
      hash   = person.to_h

      expect(hash[:first_name]).to eq("John")
      expect(hash.keys).to match_array(described_class::ATTRIBUTES.keys)
    end
  end

  describe "equality" do
    it "considers persons with the same attributes equal" do
      a = described_class.new(full_attrs)
      b = described_class.new(full_attrs)

      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
    end

    it "considers persons with different attributes unequal" do
      a = described_class.new(full_attrs)
      b = described_class.new(full_attrs.merge("FirstName" => "Jane"))

      expect(a).not_to eq(b)
    end
  end

  describe "#inspect" do
    it "includes the name and email" do
      person = described_class.new(full_attrs)

      expect(person.inspect).to include("first_name=")
      expect(person.inspect).to include("email_address=")
    end
  end
end
