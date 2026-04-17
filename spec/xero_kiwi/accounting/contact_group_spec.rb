# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::ContactGroup do
  let(:full_attrs) do
    {
      "ContactGroupID" => "97bbd0e6-ab4d-4117-9304-d90dd4779199",
      "Name"           => "VIP Customers",
      "Status"         => "ACTIVE",
      "Contacts"       => [
        { "ContactID" => "9ce626d2-14ea-463c-9fff-6785ab5f9bfb", "Name" => "Boom FM" },
        { "ContactID" => "b9d4332a-26a3-4577-8db2-6e830d4b07cd", "Name" => "Berry Brew" }
      ]
    }
  end

  describe ".from_response" do
    it "parses ContactGroups from the Xero response envelope" do
      payload = { "ContactGroups" => [full_attrs] }
      groups  = described_class.from_response(payload)

      expect(groups).to all(be_a(described_class))
      expect(groups.first.contact_group_id).to eq("97bbd0e6-ab4d-4117-9304-d90dd4779199")
    end

    it "returns multiple groups when present" do
      second  = full_attrs.merge("ContactGroupID" => "abc-123", "Name" => "Preferred Suppliers")
      payload = { "ContactGroups" => [full_attrs, second] }

      expect(described_class.from_response(payload).size).to eq(2)
    end

    it "returns an empty array when payload is nil" do
      expect(described_class.from_response(nil)).to eq([])
    end

    it "returns an empty array when ContactGroups key is missing" do
      expect(described_class.from_response({})).to eq([])
    end

    it "returns an empty array when ContactGroups array is empty" do
      expect(described_class.from_response("ContactGroups" => [])).to eq([])
    end
  end

  describe "#initialize" do
    subject(:group) { described_class.new(full_attrs) }

    it "maps all attributes" do
      expect(group).to have_attributes(
        contact_group_id: "97bbd0e6-ab4d-4117-9304-d90dd4779199",
        name:             "VIP Customers",
        status:           "ACTIVE"
      )
    end

    it "wraps contacts as XeroKiwi::Accounting::Contact references" do
      expect(group.contacts.size).to eq(2)
      expect(group.contacts).to all(be_a(XeroKiwi::Accounting::Contact))
      expect(group.contacts.first.contact_id).to eq("9ce626d2-14ea-463c-9fff-6785ab5f9bfb")
      expect(group.contacts.first.name).to eq("Boom FM")
      expect(group.contacts.first.reference?).to be true
    end

    it "defaults contacts to an empty array when absent" do
      group = described_class.new({ "ContactGroupID" => "abc", "Name" => "Test" })
      expect(group.contacts).to eq([])
    end
  end

  describe "#reference?" do
    it "returns false by default" do
      expect(described_class.new(full_attrs).reference?).to be false
    end

    it "returns true when constructed with reference: true" do
      group = described_class.new(full_attrs, reference: true)
      expect(group.reference?).to be true
    end
  end

  describe "#active?" do
    it "returns true when Status is ACTIVE" do
      expect(described_class.new(full_attrs).active?).to be true
    end

    it "returns false when Status is not ACTIVE" do
      group = described_class.new(full_attrs.merge("Status" => "DELETED"))
      expect(group.active?).to be false
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      group = described_class.new(full_attrs)
      hash  = group.to_h

      expect(hash[:contact_group_id]).to eq("97bbd0e6-ab4d-4117-9304-d90dd4779199")
      expect(hash[:name]).to eq("VIP Customers")
      expect(hash.keys).to match_array(described_class.attributes.keys)
    end
  end

  describe "equality" do
    it "considers two groups equal when they share the same contact_group_id" do
      a = described_class.new({ "ContactGroupID" => "abc", "Name" => "A" })
      b = described_class.new({ "ContactGroupID" => "abc", "Name" => "B" })

      expect(a).to eq(b)
      expect(a).to eql(b)
      expect(a.hash).to eq(b.hash)
    end

    it "considers groups with different IDs unequal" do
      a = described_class.new({ "ContactGroupID" => "abc" })
      b = described_class.new({ "ContactGroupID" => "xyz" })

      expect(a).not_to eq(b)
    end
  end

  describe "#inspect" do
    it "includes the id, name, and status" do
      group = described_class.new(full_attrs)

      expect(group.inspect).to include("contact_group_id=")
      expect(group.inspect).to include("name=")
      expect(group.inspect).to include("status=")
    end
  end
end
