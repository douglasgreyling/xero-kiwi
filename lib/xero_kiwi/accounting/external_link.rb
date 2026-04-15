# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # A Xero external link (social/web profile). Used by Organisation.
    #
    # See: https://developer.xero.com/documentation/api/accounting/types#externallinks
    class ExternalLink
      ATTRIBUTES = {
        link_type: "LinkType",
        url:       "Url"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def initialize(attrs)
        attrs      = attrs.transform_keys(&:to_s)
        @link_type = attrs["LinkType"]
        @url       = attrs["Url"]
      end

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(ExternalLink) && to_h == other.to_h
      end
      alias eql? ==

      def hash = to_h.hash

      def inspect
        "#<#{self.class} type=#{link_type.inspect} url=#{url.inspect}>"
      end
    end
  end
end
