# frozen_string_literal: true

require "time"

module XeroKiwi
  module Accounting
    # Represents a Xero Overpayment returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/overpayments
    class Overpayment
      ATTRIBUTES = {
        overpayment_id:    "OverpaymentID",
        type:              "Type",
        contact:           "Contact",
        date:              "Date",
        status:            "Status",
        line_amount_types: "LineAmountTypes",
        line_items:        "LineItems",
        sub_total:         "SubTotal",
        total_tax:         "TotalTax",
        total:             "Total",
        updated_date_utc:  "UpdatedDateUTC",
        currency_code:     "CurrencyCode",
        currency_rate:     "CurrencyRate",
        remaining_credit:  "RemainingCredit",
        allocations:       "Allocations",
        payments:          "Payments",
        has_attachments:   "HasAttachments",
        reference:         "Reference"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def self.from_response(payload)
        return [] if payload.nil?

        items = payload["Overpayments"]
        return [] if items.nil?

        items.map { |attrs| new(attrs) }
      end

      def initialize(attrs, reference: false) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
        attrs              = attrs.transform_keys(&:to_s)
        @is_reference      = reference
        @overpayment_id    = attrs["OverpaymentID"]
        @type              = attrs["Type"]
        @contact           = attrs["Contact"] ? Contact.new(attrs["Contact"], reference: true) : nil
        @date              = parse_time(attrs["Date"])
        @status            = attrs["Status"]
        @line_amount_types = attrs["LineAmountTypes"]
        @line_items        = (attrs["LineItems"] || []).map { |li| LineItem.new(li) }
        @sub_total         = attrs["SubTotal"]
        @total_tax         = attrs["TotalTax"]
        @total             = attrs["Total"]
        @updated_date_utc  = parse_time(attrs["UpdatedDateUTC"])
        @currency_code     = attrs["CurrencyCode"]
        @currency_rate     = attrs["CurrencyRate"]
        @remaining_credit  = attrs["RemainingCredit"]
        @allocations       = (attrs["Allocations"] || []).map { |a| Allocation.new(a) }
        @payments          = (attrs["Payments"] || []).map { |p| Payment.new(p, reference: true) }
        @has_attachments   = attrs["HasAttachments"]
        @reference         = attrs["Reference"]
      end

      def receive? = type == "RECEIVE-OVERPAYMENT"

      def spend? = type == "SPEND-OVERPAYMENT"

      def reference? = @is_reference

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(Overpayment) && other.overpayment_id == overpayment_id
      end
      alias eql? ==

      def hash = [self.class, overpayment_id].hash

      def inspect
        "#<#{self.class} overpayment_id=#{overpayment_id.inspect} " \
          "type=#{type.inspect} status=#{status.inspect} total=#{total.inspect}>"
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
