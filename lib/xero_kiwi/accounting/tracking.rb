# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # A tracking assignment — one category and the single option chosen for
    # it — as nested on a line item (`Tracking`) or a contact. This is not
    # the same shape as the /TrackingCategories endpoint returns; see
    # Accounting::TrackingCategory for that.
    #
    # See: https://developer.xero.com/documentation/api/accounting/invoices
    class Tracking
      include Resource

      attribute :tracking_category_id, xero: "TrackingCategoryID", type: :guid
      attribute :tracking_option_id,   xero: "TrackingOptionID",   type: :guid
      attribute :name,                 xero: "Name"
      attribute :option,               xero: "Option"
    end
  end
end
