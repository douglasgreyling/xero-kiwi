# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # A Xero phone number. Used by Organisation, Contact, and other resources.
    #
    # See: https://developer.xero.com/documentation/api/accounting/types#phones
    class Phone
      include Resource

      attribute :phone_type,         xero: "PhoneType"
      attribute :phone_number,       xero: "PhoneNumber"
      attribute :phone_area_code,    xero: "PhoneAreaCode"
      attribute :phone_country_code, xero: "PhoneCountryCode"

      def default? = phone_type == "DEFAULT"
      def mobile?  = phone_type == "MOBILE"
      def fax?     = phone_type == "FAX"
    end
  end
end
