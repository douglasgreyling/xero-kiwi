# frozen_string_literal: true

require "time"

module XeroKiwi
  module Accounting
    # Represents an allocation of a credit note, prepayment, or overpayment
    # against an invoice.
    #
    # See: https://developer.xero.com/documentation/api/accounting/overpayments
    class Allocation
      ATTRIBUTES = {
        allocation_id: "AllocationID",
        amount:        "Amount",
        date:          "Date",
        invoice:       "Invoice",
        is_deleted:    "IsDeleted"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def initialize(attrs)
        attrs          = attrs.transform_keys(&:to_s)
        @allocation_id = attrs["AllocationID"]
        @amount        = attrs["Amount"]
        @date          = parse_time(attrs["Date"])
        @invoice       = attrs["Invoice"] ? Invoice.new(attrs["Invoice"], reference: true) : nil
        @is_deleted    = attrs["IsDeleted"]
      end

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(Allocation) && other.allocation_id == allocation_id
      end
      alias eql? ==

      def hash = [self.class, allocation_id].hash

      def inspect
        "#<#{self.class} allocation_id=#{allocation_id.inspect} " \
          "amount=#{amount.inspect}>"
      end

      private

      def parse_time(value)
        return nil if value.nil?

        str = value.to_s.strip
        return nil if str.empty?

        if (match = str.match(%r{\A/Date\((\d+)([+-]\d{4})?\)/\z}))
          Time.at(match[1].to_i / 1000.0).utc
        else
          str = "#{str}Z" unless str.match?(/[Zz]\z|[+-]\d{2}:?\d{2}\z/)
          Time.iso8601(str)
        end
      rescue ArgumentError
        nil
      end
    end
  end
end
