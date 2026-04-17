# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::BrandingTheme do
  let(:full_attrs) do
    {
      "BrandingThemeID" => "dfe23d27-a3a6-4ef3-a5ca-b9e02b142dde",
      "Name"            => "Special Projects",
      "LogoUrl"         => "https://in.xero.com/logo?id=abc123",
      "Type"            => "INVOICE",
      "SortOrder"       => 1,
      "CreatedDateUTC"  => "/Date(946684800000+0000)/"
    }
  end

  describe ".from_response" do
    it "parses BrandingThemes from the Xero response envelope" do
      payload = { "BrandingThemes" => [full_attrs] }
      themes  = described_class.from_response(payload)

      expect(themes).to all(be_a(described_class))
      expect(themes.first.branding_theme_id).to eq("dfe23d27-a3a6-4ef3-a5ca-b9e02b142dde")
    end

    it "returns multiple themes when present" do
      second  = full_attrs.merge("BrandingThemeID" => "abc-123", "Name" => "Standard")
      payload = { "BrandingThemes" => [full_attrs, second] }

      expect(described_class.from_response(payload).size).to eq(2)
    end

    it "returns an empty array when payload is nil" do
      expect(described_class.from_response(nil)).to eq([])
    end

    it "returns an empty array when BrandingThemes key is missing" do
      expect(described_class.from_response({})).to eq([])
    end

    it "returns an empty array when BrandingThemes array is empty" do
      expect(described_class.from_response("BrandingThemes" => [])).to eq([])
    end
  end

  describe "#initialize" do
    subject(:theme) { described_class.new(full_attrs) }

    it "maps all attributes" do
      expect(theme).to have_attributes(
        branding_theme_id: "dfe23d27-a3a6-4ef3-a5ca-b9e02b142dde",
        name:              "Special Projects",
        logo_url:          "https://in.xero.com/logo?id=abc123",
        type:              "INVOICE",
        sort_order:        1
      )
    end

    it "parses CreatedDateUTC in .NET JSON format into a UTC Time" do
      expect(theme.created_date_utc).to be_a(Time)
      expect(theme.created_date_utc.utc_offset).to eq(0)
    end

    it "parses CreatedDateUTC in ISO 8601 format" do
      attrs = full_attrs.merge("CreatedDateUTC" => "2019-07-09T23:40:30.1833130")
      theme = described_class.new(attrs)

      expect(theme.created_date_utc).to be_a(Time)
      expect(theme.created_date_utc.utc_offset).to eq(0)
    end

    it "handles nil CreatedDateUTC gracefully" do
      attrs = full_attrs.merge("CreatedDateUTC" => nil)
      theme = described_class.new(attrs)

      expect(theme.created_date_utc).to be_nil
    end

    it "handles nil LogoUrl gracefully" do
      attrs = full_attrs.except("LogoUrl")
      theme = described_class.new(attrs)

      expect(theme.logo_url).to be_nil
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      theme = described_class.new(full_attrs)
      hash  = theme.to_h

      expect(hash[:branding_theme_id]).to eq("dfe23d27-a3a6-4ef3-a5ca-b9e02b142dde")
      expect(hash[:name]).to eq("Special Projects")
      expect(hash.keys).to match_array(described_class.attributes.keys)
    end
  end

  describe "equality" do
    it "considers two themes equal when they share the same branding_theme_id" do
      a = described_class.new("BrandingThemeID" => "abc", "Name" => "A")
      b = described_class.new("BrandingThemeID" => "abc", "Name" => "B")

      expect(a).to eq(b)
      expect(a).to eql(b)
      expect(a.hash).to eq(b.hash)
    end

    it "considers themes with different IDs unequal" do
      a = described_class.new("BrandingThemeID" => "abc")
      b = described_class.new("BrandingThemeID" => "xyz")

      expect(a).not_to eq(b)
    end
  end

  describe "#inspect" do
    it "includes the id, name, and type" do
      theme = described_class.new(full_attrs)
      expect(theme.inspect).to include("branding_theme_id=")
      expect(theme.inspect).to include("name=")
      expect(theme.inspect).to include("type=")
    end
  end
end
