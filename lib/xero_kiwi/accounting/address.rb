# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # A Xero address. Used by Organisation, Contact, and other resources.
    #
    # See: https://developer.xero.com/documentation/api/accounting/types#addresses
    class Address
      include Resource

      attribute :address_type,   xero: "AddressType"
      attribute :address_line_1, xero: "AddressLine1"
      attribute :address_line_2, xero: "AddressLine2"
      attribute :address_line_3, xero: "AddressLine3"
      attribute :address_line_4, xero: "AddressLine4"
      attribute :city,           xero: "City"
      attribute :region,         xero: "Region"
      attribute :postal_code,    xero: "PostalCode"
      attribute :country,        xero: "Country"
      attribute :attention_to,   xero: "AttentionTo"

      def street?   = address_type == "STREET"
      def pobox?    = address_type == "POBOX"
      def delivery? = address_type == "DELIVERY"
    end
  end
end
