# frozen_string_literal: true

require_relative "query/filter"
require_relative "query/order"

module XeroKiwi
  # Compilers that translate Ruby-native query inputs (Hashes, Ranges, Arrays,
  # etc.) into Xero's `where` filter expressions and `order` sort strings.
  #
  # See `XeroKiwi::Query::Filter` and `XeroKiwi::Query::Order`.
  module Query
  end
end
