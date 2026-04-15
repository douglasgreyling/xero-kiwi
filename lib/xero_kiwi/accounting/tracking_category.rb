# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a tracking category assignment on a line item or contact.
    #
    # See: https://developer.xero.com/documentation/api/accounting/invoices
    class TrackingCategory
      ATTRIBUTES = {
        tracking_category_id: "TrackingCategoryID",
        tracking_option_id:   "TrackingOptionID",
        name:                 "Name",
        option:               "Option"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def initialize(attrs)
        attrs                 = attrs.transform_keys(&:to_s)
        @tracking_category_id = attrs["TrackingCategoryID"]
        @tracking_option_id   = attrs["TrackingOptionID"]
        @name                 = attrs["Name"]
        @option               = attrs["Option"]
      end

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(TrackingCategory) && to_h == other.to_h
      end
      alias eql? ==

      def hash = to_h.hash

      def inspect
        "#<#{self.class} name=#{name.inspect} option=#{option.inspect}>"
      end
    end
  end
end
