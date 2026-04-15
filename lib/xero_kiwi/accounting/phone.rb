# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # A Xero phone number. Used by Organisation, Contact, and other resources.
    #
    # See: https://developer.xero.com/documentation/api/accounting/types#phones
    class Phone
      ATTRIBUTES = {
        phone_type:         "PhoneType",
        phone_number:       "PhoneNumber",
        phone_area_code:    "PhoneAreaCode",
        phone_country_code: "PhoneCountryCode"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def initialize(attrs)
        attrs               = attrs.transform_keys(&:to_s)
        @phone_type         = attrs["PhoneType"]
        @phone_number       = attrs["PhoneNumber"]
        @phone_area_code    = attrs["PhoneAreaCode"]
        @phone_country_code = attrs["PhoneCountryCode"]
      end

      def default? = phone_type == "DEFAULT"
      def mobile?  = phone_type == "MOBILE"
      def fax?     = phone_type == "FAX"

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(Phone) && to_h == other.to_h
      end
      alias eql? ==

      def hash = to_h.hash

      def inspect
        "#<#{self.class} type=#{phone_type.inspect} number=#{phone_number.inspect}>"
      end
    end
  end
end
