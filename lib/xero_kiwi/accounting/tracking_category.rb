# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a tracking category assignment on a line item or contact.
    #
    # See: https://developer.xero.com/documentation/api/accounting/invoices
    class TrackingCategory
      include Resource

      attribute :tracking_category_id, xero: "TrackingCategoryID", type: :guid
      attribute :tracking_option_id,   xero: "TrackingOptionID",   type: :guid
      attribute :name,                 xero: "Name"
      attribute :option,               xero: "Option"
    end
  end
end
