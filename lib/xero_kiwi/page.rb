# frozen_string_literal: true

module XeroKiwi
  # A paginated list result from a Xero endpoint. Wraps the items with the
  # pagination metadata Xero returns in the response envelope when `page=` is
  # passed. Behaves like an Array for iteration and collection methods
  # (Enumerable + `size` / `empty?` / `to_a`), so most callers can keep
  # working with the value directly.
  #
  # Callers that need raw Array behaviour (mutation, slicing, `JSON.dump`,
  # `is_a?(Array)` checks) should call `.to_a`.
  class Page
    include Enumerable

    attr_reader :items, :page, :page_size, :item_count, :total_count

    def initialize(items:, page: nil, page_size: nil, item_count: nil, total_count: nil)
      @items       = items
      @page        = page
      @page_size   = page_size
      @item_count  = item_count
      @total_count = total_count
    end

    def each(&block)
      return to_enum(:each) unless block

      @items.each(&block)
    end

    def size
      @items.size
    end
    alias length size

    def empty?
      @items.empty?
    end

    def to_a
      @items.dup
    end

    def inspect
      "#<#{self.class} items=#{size} page=#{page.inspect} " \
        "page_size=#{page_size.inspect} item_count=#{item_count.inspect}>"
    end
  end
end
