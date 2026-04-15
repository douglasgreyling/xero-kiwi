# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::ExternalLink do
  describe "#initialize" do
    it "maps all attributes" do
      link = described_class.new("LinkType" => "Facebook", "Url" => "https://facebook.com/example")

      expect(link).to have_attributes(
        link_type: "Facebook",
        url:       "https://facebook.com/example"
      )
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      link = described_class.new("LinkType" => "Twitter", "Url" => "https://twitter.com/example")
      expect(link.to_h).to eq(link_type: "Twitter", url: "https://twitter.com/example")
    end
  end

  describe "equality" do
    it "considers links with the same attributes equal" do
      a = described_class.new("LinkType" => "Website", "Url" => "https://example.com")
      b = described_class.new("LinkType" => "Website", "Url" => "https://example.com")

      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
    end

    it "considers links with different attributes unequal" do
      a = described_class.new("LinkType" => "Website", "Url" => "https://a.com")
      b = described_class.new("LinkType" => "Website", "Url" => "https://b.com")

      expect(a).not_to eq(b)
    end
  end
end
