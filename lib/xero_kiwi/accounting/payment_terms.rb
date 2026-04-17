# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Xero payment terms for an Organisation or Contact, containing separate
    # terms for bills (payable) and sales (receivable).
    #
    # See: https://developer.xero.com/documentation/api/accounting/types#paymentterms
    class PaymentTerms
      include Resource

      # A nil or empty sub-hash should collapse to nil rather than constructing
      # a PaymentTerm with every attribute nil.
      TERM_HYDRATOR = ->(raw) { raw.nil? || raw.empty? ? nil : PaymentTerm.new(raw) }

      attribute :bills, xero: "Bills", hydrate: TERM_HYDRATOR
      attribute :sales, xero: "Sales", hydrate: TERM_HYDRATOR

      def self.from_hash(hash)
        return nil if hash.nil?

        new(hash)
      end

      # Override the mixin default: PaymentTerms's to_h unwraps the nested
      # PaymentTerm objects to hashes, matching the pre-DSL behaviour.
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
      include Resource

      attribute :day,  xero: "Day"
      attribute :type, xero: "Type"

      def self.from_hash(hash)
        return nil if hash.nil? || hash.empty?

        new(hash)
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
