# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # A Xero address. Used by Organisation, Contact, and other resources.
    #
    # See: https://developer.xero.com/documentation/api/accounting/types#addresses
    class Address
      ATTRIBUTES = {
        address_type:   "AddressType",
        address_line_1: "AddressLine1",
        address_line_2: "AddressLine2",
        address_line_3: "AddressLine3",
        address_line_4: "AddressLine4",
        city:           "City",
        region:         "Region",
        postal_code:    "PostalCode",
        country:        "Country",
        attention_to:   "AttentionTo"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def initialize(attrs)
        attrs           = attrs.transform_keys(&:to_s)
        @address_type   = attrs["AddressType"]
        @address_line_1 = attrs["AddressLine1"]
        @address_line_2 = attrs["AddressLine2"]
        @address_line_3 = attrs["AddressLine3"]
        @address_line_4 = attrs["AddressLine4"]
        @city           = attrs["City"]
        @region         = attrs["Region"]
        @postal_code    = attrs["PostalCode"]
        @country        = attrs["Country"]
        @attention_to   = attrs["AttentionTo"]
      end

      def street?   = address_type == "STREET"
      def pobox?    = address_type == "POBOX"
      def delivery? = address_type == "DELIVERY"

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(Address) && to_h == other.to_h
      end
      alias eql? ==

      def hash = to_h.hash

      def inspect
        "#<#{self.class} type=#{address_type.inspect} city=#{city.inspect} country=#{country.inspect}>"
      end
    end
  end
end
