# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Xero payment terms for an Organisation or Contact, containing separate
    # terms for bills (payable) and sales (receivable).
    #
    # See: https://developer.xero.com/documentation/api/accounting/types#paymentterms
    class PaymentTerms
      attr_reader :bills, :sales

      def self.from_hash(hash)
        return nil if hash.nil?

        new(hash)
      end

      def initialize(attrs)
        attrs  = attrs.transform_keys(&:to_s)
        @bills = PaymentTerm.from_hash(attrs["Bills"])
        @sales = PaymentTerm.from_hash(attrs["Sales"])
      end

      def to_h
        { bills: bills&.to_h, sales: sales&.to_h }
      end

      def ==(other)
        other.is_a?(PaymentTerms) && bills == other.bills && sales == other.sales
      end
      alias eql? ==

      def hash = [self.class, bills, sales].hash

      def inspect
        "#<#{self.class} bills=#{bills.inspect} sales=#{sales.inspect}>"
      end
    end

    # A single payment term (either bills or sales side).
    class PaymentTerm
      ATTRIBUTES = {
        day:  "Day",
        type: "Type"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def self.from_hash(hash)
        return nil if hash.nil? || hash.empty?

        new(hash)
      end

      def initialize(attrs)
        attrs = attrs.transform_keys(&:to_s)
        @day  = attrs["Day"]
        @type = attrs["Type"]
      end

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(PaymentTerm) && day == other.day && type == other.type
      end
      alias eql? ==

      def hash = [self.class, day, type].hash

      def inspect
        "#<#{self.class} day=#{day.inspect} type=#{type.inspect}>"
      end
    end
  end
end
