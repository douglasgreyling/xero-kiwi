# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # One selectable option within a tracking category, as returned nested in
    # the /TrackingCategories response.
    #
    # See: https://developer.xero.com/documentation/api/accounting/trackingcategories
    class TrackingOption
      include Resource

      payload_key "Options"
      identity    :tracking_option_id

      attribute :tracking_option_id, xero: "TrackingOptionID", type: :guid
      attribute :name,               xero: "Name",             query: true
      attribute :status,             xero: "Status",           type: :enum, query: true

      def active? = status == "ACTIVE"
    end
  end
end
