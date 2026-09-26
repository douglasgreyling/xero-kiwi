# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # A tracking category *definition* as returned by /TrackingCategories —
    # the category itself plus the options available under it.
    #
    # Not to be confused with Accounting::Tracking, which is the flattened
    # category-and-chosen-option pair nested on line items and contacts.
    #
    # See: https://developer.xero.com/documentation/api/accounting/trackingcategories
    class TrackingCategory
      include Resource

      payload_key "TrackingCategories"
      identity    :tracking_category_id

      attribute :tracking_category_id, xero: "TrackingCategoryID", type: :guid
      attribute :name,                 xero: "Name",               query: true
      attribute :status,               xero: "Status",             type: :enum, query: true
      attribute :options,              xero: "Options",            type: :collection, of: TrackingOption

      def active? = status == "ACTIVE"
    end
  end
end
