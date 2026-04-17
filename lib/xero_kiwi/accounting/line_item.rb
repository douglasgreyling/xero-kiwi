# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a line item nested within Xero documents (invoices, credit
    # notes, prepayments, overpayments).
    #
    # See: https://developer.xero.com/documentation/api/accounting/invoices
    class LineItem
      include Resource

      attribute :line_item_id,    xero: "LineItemID", type: :guid
      attribute :description,     xero: "Description"
      attribute :quantity,        xero: "Quantity",       type: :decimal
      attribute :unit_amount,     xero: "UnitAmount",     type: :decimal
      attribute :item_code,       xero: "ItemCode"
      attribute :account_code,    xero: "AccountCode"
      attribute :account_id,      xero: "AccountId", type: :guid
      attribute :tax_type,        xero: "TaxType"
      attribute :tax_amount,      xero: "TaxAmount",      type: :decimal
      attribute :line_amount,     xero: "LineAmount",     type: :decimal
      attribute :discount_rate,   xero: "DiscountRate",   type: :decimal
      attribute :discount_amount, xero: "DiscountAmount", type: :decimal
      attribute :tracking,        xero: "Tracking",       type: :collection, of: TrackingCategory
      attribute :item,            xero: "Item"
    end
  end
end
