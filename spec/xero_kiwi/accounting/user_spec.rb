# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::User do
  let(:full_attrs) do
    {
      "UserID"           => "7cf47fe2-c3dd-4c6b-9895-7ba767ba529c",
      "EmailAddress"     => "john.smith@mail.com",
      "FirstName"        => "John",
      "LastName"         => "Smith",
      "UpdatedDateUTC"   => "/Date(1516230549137+0000)/",
      "IsSubscriber"     => false,
      "OrganisationRole" => "ADMIN"
    }
  end

  describe ".from_response" do
    it "parses Users from the Xero response envelope" do
      payload = { "Users" => [full_attrs] }
      users   = described_class.from_response(payload)

      expect(users).to all(be_a(described_class))
      expect(users.first.user_id).to eq("7cf47fe2-c3dd-4c6b-9895-7ba767ba529c")
    end

    it "returns multiple users when present" do
      second  = full_attrs.merge("UserID" => "abc-123", "EmailAddress" => "jane@mail.com")
      payload = { "Users" => [full_attrs, second] }

      expect(described_class.from_response(payload).size).to eq(2)
    end

    it "returns an empty array when payload is nil" do
      expect(described_class.from_response(nil)).to eq([])
    end

    it "returns an empty array when Users key is missing" do
      expect(described_class.from_response({})).to eq([])
    end

    it "returns an empty array when Users array is empty" do
      expect(described_class.from_response("Users" => [])).to eq([])
    end
  end

  describe "#initialize" do
    subject(:user) { described_class.new(full_attrs) }

    it "maps all attributes" do
      expect(user).to have_attributes(
        user_id:           "7cf47fe2-c3dd-4c6b-9895-7ba767ba529c",
        email_address:     "john.smith@mail.com",
        first_name:        "John",
        last_name:         "Smith",
        is_subscriber:     false,
        organisation_role: "ADMIN"
      )
    end

    it "parses UpdatedDateUTC in .NET JSON format into a UTC Time" do
      expect(user.updated_date_utc).to be_a(Time)
      expect(user.updated_date_utc.utc_offset).to eq(0)
    end

    it "parses UpdatedDateUTC in ISO 8601 format" do
      attrs = full_attrs.merge("UpdatedDateUTC" => "2019-07-09T23:40:30.1833130")
      user  = described_class.new(attrs)

      expect(user.updated_date_utc).to be_a(Time)
      expect(user.updated_date_utc.utc_offset).to eq(0)
    end

    it "handles nil UpdatedDateUTC gracefully" do
      attrs = full_attrs.merge("UpdatedDateUTC" => nil)
      user  = described_class.new(attrs)

      expect(user.updated_date_utc).to be_nil
    end
  end

  describe "#subscriber?" do
    it "returns true when IsSubscriber is true" do
      user = described_class.new(full_attrs.merge("IsSubscriber" => true))
      expect(user.subscriber?).to be true
    end

    it "returns false when IsSubscriber is false" do
      user = described_class.new(full_attrs.merge("IsSubscriber" => false))
      expect(user.subscriber?).to be false
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      user = described_class.new(full_attrs)
      hash = user.to_h

      expect(hash[:user_id]).to eq("7cf47fe2-c3dd-4c6b-9895-7ba767ba529c")
      expect(hash[:email_address]).to eq("john.smith@mail.com")
      expect(hash.keys).to match_array(described_class::ATTRIBUTES.keys)
    end
  end

  describe "equality" do
    it "considers two users equal when they share the same user_id" do
      a = described_class.new("UserID" => "abc", "FirstName" => "A")
      b = described_class.new("UserID" => "abc", "FirstName" => "B")

      expect(a).to eq(b)
      expect(a).to eql(b)
      expect(a.hash).to eq(b.hash)
    end

    it "considers users with different IDs unequal" do
      a = described_class.new("UserID" => "abc")
      b = described_class.new("UserID" => "xyz")

      expect(a).not_to eq(b)
    end
  end

  describe "#inspect" do
    it "includes the id, email, and role" do
      user = described_class.new(full_attrs)
      expect(user.inspect).to include("user_id=")
      expect(user.inspect).to include("email_address=")
      expect(user.inspect).to include("organisation_role=")
    end
  end
end
