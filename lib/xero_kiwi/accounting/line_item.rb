# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a line item nested within Xero documents (invoices, credit
    # notes, prepayments, overpayments).
    #
    # See: https://developer.xero.com/documentation/api/accounting/invoices
    class LineItem
      ATTRIBUTES = {
        line_item_id:    "LineItemID",
        description:     "Description",
        quantity:        "Quantity",
        unit_amount:     "UnitAmount",
        item_code:       "ItemCode",
        account_code:    "AccountCode",
        account_id:      "AccountId",
        tax_type:        "TaxType",
        tax_amount:      "TaxAmount",
        line_amount:     "LineAmount",
        discount_rate:   "DiscountRate",
        discount_amount: "DiscountAmount",
        tracking:        "Tracking",
        item:            "Item"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def initialize(attrs) # rubocop:disable Metrics/AbcSize
        attrs            = attrs.transform_keys(&:to_s)
        @line_item_id    = attrs["LineItemID"]
        @description     = attrs["Description"]
        @quantity        = attrs["Quantity"]
        @unit_amount     = attrs["UnitAmount"]
        @item_code       = attrs["ItemCode"]
        @account_code    = attrs["AccountCode"]
        @account_id      = attrs["AccountId"]
        @tax_type        = attrs["TaxType"]
        @tax_amount      = attrs["TaxAmount"]
        @line_amount     = attrs["LineAmount"]
        @discount_rate   = attrs["DiscountRate"]
        @discount_amount = attrs["DiscountAmount"]
        @tracking        = (attrs["Tracking"] || []).map { |t| TrackingCategory.new(t) }
        @item            = attrs["Item"]
      end

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(LineItem) && to_h == other.to_h
      end
      alias eql? ==

      def hash = to_h.hash

      def inspect
        "#<#{self.class} description=#{description.inspect} " \
          "line_amount=#{line_amount.inspect}>"
      end
    end
  end
end
