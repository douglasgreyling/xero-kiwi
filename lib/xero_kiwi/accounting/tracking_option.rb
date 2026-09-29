# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # One selectable option within a tracking category, as returned nested in
    # the /TrackingCategories response.
    #
    # Xero sends both `Status` and a set of booleans that overlap it. They
    # agree on an active option; whether they diverge on an archived or
    # deleted one is unconfirmed, so `#active?` stays on `Status` and the
    # booleans are exposed for callers who need the distinction.
    #
    # See: https://developer.xero.com/documentation/api/accounting/trackingcategories
    class TrackingOption
      include Resource

      payload_key "Options"
      identity    :tracking_option_id

      attribute :tracking_option_id,    xero: "TrackingOptionID",     type: :guid
      attribute :name,                  xero: "Name",                 query: true
      attribute :status,                xero: "Status",               type: :enum, query: true
      attribute :is_active,             xero: "IsActive",             type: :bool
      attribute :is_archived,           xero: "IsArchived",           type: :bool
      attribute :is_deleted,            xero: "IsDeleted",            type: :bool
      attribute :has_validation_errors, xero: "HasValidationErrors",  type: :bool

      def active? = status == "ACTIVE"
    end
  end
end
