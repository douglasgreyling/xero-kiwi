# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a Xero Branding Theme returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/brandingthemes
    class BrandingTheme
      include Resource

      payload_key "BrandingThemes"
      identity    :branding_theme_id

      attribute :branding_theme_id, xero: "BrandingThemeID", type: :guid
      attribute :name,              xero: "Name", query: true
      attribute :logo_url,          xero: "LogoUrl"
      attribute :type,              xero: "Type"
      attribute :sort_order,        xero: "SortOrder"
      attribute :created_date_utc,  xero: "CreatedDateUTC", type: :date
    end
  end
end
