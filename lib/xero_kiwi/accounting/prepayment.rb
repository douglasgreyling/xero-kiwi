# frozen_string_literal: true

require "time"

module XeroKiwi
  module Accounting
    # Represents a Xero Prepayment returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/prepayments
    class Prepayment
      ATTRIBUTES = {
        prepayment_id:      "PrepaymentID",
        type:               "Type",
        contact:            "Contact",
        date:               "Date",
        status:             "Status",
        line_amount_types:  "LineAmountTypes",
        line_items:         "LineItems",
        sub_total:          "SubTotal",
        total_tax:          "TotalTax",
        total:              "Total",
        updated_date_utc:   "UpdatedDateUTC",
        currency_code:      "CurrencyCode",
        currency_rate:      "CurrencyRate",
        invoice_number:     "InvoiceNumber",
        remaining_credit:   "RemainingCredit",
        allocations:        "Allocations",
        payments:           "Payments",
        has_attachments:    "HasAttachments",
        fully_paid_on_date: "FullyPaidOnDate"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def self.from_response(payload)
        return [] if payload.nil?

        items = payload["Prepayments"]
        return [] if items.nil?

        items.map { |attrs| new(attrs) }
      end

      def initialize(attrs, reference: false) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
        attrs               = attrs.transform_keys(&:to_s)
        @is_reference       = reference
        @prepayment_id      = attrs["PrepaymentID"]
        @type               = attrs["Type"]
        @contact            = attrs["Contact"] ? Contact.new(attrs["Contact"], reference: true) : nil
        @date               = parse_time(attrs["Date"])
        @status             = attrs["Status"]
        @line_amount_types  = attrs["LineAmountTypes"]
        @line_items         = (attrs["LineItems"] || []).map { |li| LineItem.new(li) }
        @sub_total          = attrs["SubTotal"]
        @total_tax          = attrs["TotalTax"]
        @total              = attrs["Total"]
        @updated_date_utc   = parse_time(attrs["UpdatedDateUTC"])
        @currency_code      = attrs["CurrencyCode"]
        @currency_rate      = attrs["CurrencyRate"]
        @invoice_number     = attrs["InvoiceNumber"]
        @remaining_credit   = attrs["RemainingCredit"]
        @allocations        = (attrs["Allocations"] || []).map { |a| Allocation.new(a) }
        @payments           = (attrs["Payments"] || []).map { |p| Payment.new(p, reference: true) }
        @has_attachments    = attrs["HasAttachments"]
        @fully_paid_on_date = parse_time(attrs["FullyPaidOnDate"])
      end

      def reference? = @is_reference

      def receive? = type == "RECEIVE-PREPAYMENT"

      def spend? = type == "SPEND-PREPAYMENT"

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(Prepayment) && other.prepayment_id == prepayment_id
      end
      alias eql? ==

      def hash = [self.class, prepayment_id].hash

      def inspect
        "#<#{self.class} prepayment_id=#{prepayment_id.inspect} " \
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
