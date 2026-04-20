# frozen_string_literal: true

RSpec.describe XeroKiwi::Page do
  let(:items) { [1, 2, 3] }

  describe "Enumerable delegation" do
    subject(:page) { described_class.new(items: items, page: 1, page_size: 100) }

    it "iterates via each" do
      collected = page.map { |i| i }

      expect(collected).to eq(items)
    end

    it "supports map" do
      expect(page.map { |i| i * 2 }).to eq([2, 4, 6])
    end

    it "supports first" do
      expect(page.first).to eq(1)
      expect(page.first(2)).to eq([1, 2])
    end

    it "supports select" do
      expect(page.select(&:odd?)).to eq([1, 3])
    end

    it "supports count without a block" do
      expect(page.count).to eq(3)
    end

    it "returns an enumerator when each is called without a block" do
      expect(page.each).to be_a(Enumerator)
      expect(page.each.to_a).to eq(items)
    end
  end

  describe "#size / #length / #empty?" do
    it "reports item count" do
      page = described_class.new(items: items)

      expect(page.size).to eq(3)
      expect(page.length).to eq(3)
      expect(page.empty?).to be false
    end

    it "is empty when items is empty" do
      page = described_class.new(items: [])

      expect(page.empty?).to be true
      expect(page.size).to eq(0)
    end
  end

  describe "#to_a" do
    it "returns a duplicate of items" do
      page   = described_class.new(items: items)
      copied = page.to_a

      expect(copied).to eq(items)
      expect(copied).not_to equal(items)
    end
  end

  describe "pagination metadata" do
    it "exposes every metadata attribute" do
      page = described_class.new(
        items: items, page: 2, page_size: 100, item_count: 150, total_count: 150
      )

      expect(page).to have_attributes(
        page:        2,
        page_size:   100,
        item_count:  150,
        total_count: 150
      )
    end

    it "defaults all metadata to nil when only items given" do
      page = described_class.new(items: items)

      expect(page).to have_attributes(
        page:        nil,
        page_size:   nil,
        item_count:  nil,
        total_count: nil
      )
    end
  end
end
