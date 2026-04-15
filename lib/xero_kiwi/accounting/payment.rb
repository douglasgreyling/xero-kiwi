# frozen_string_literal: true

require "time"

module XeroKiwi
  module Accounting
    # Represents a Xero Payment returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/payments
    class Payment
      ATTRIBUTES = {
        payment_id:       "PaymentID",
        date:             "Date",
        currency_rate:    "CurrencyRate",
        amount:           "Amount",
        bank_amount:      "BankAmount",
        reference:        "Reference",
        is_reconciled:    "IsReconciled",
        status:           "Status",
        payment_type:     "PaymentType",
        updated_date_utc: "UpdatedDateUTC",
        batch_payment_id: "BatchPaymentID",
        batch_payment:    "BatchPayment",
        account:          "Account",
        invoice:          "Invoice",
        credit_note:      "CreditNote",
        prepayment:       "Prepayment",
        overpayment:      "Overpayment",
        has_account:      "HasAccount"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def self.from_response(payload)
        return [] if payload.nil?

        items = payload["Payments"]
        return [] if items.nil?

        items.map { |attrs| new(attrs) }
      end

      def initialize(attrs, reference: false) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        attrs              = attrs.transform_keys(&:to_s)
        @is_reference      = reference
        @payment_id        = attrs["PaymentID"]
        @date              = parse_time(attrs["Date"])
        @currency_rate     = attrs["CurrencyRate"]
        @amount            = attrs["Amount"]
        @bank_amount       = attrs["BankAmount"]
        @reference         = attrs["Reference"]
        @is_reconciled     = attrs["IsReconciled"]
        @status            = attrs["Status"]
        @payment_type      = attrs["PaymentType"]
        @updated_date_utc  = parse_time(attrs["UpdatedDateUTC"])
        @batch_payment_id  = attrs["BatchPaymentID"]
        @batch_payment     = attrs["BatchPayment"]
        @account           = attrs["Account"]
        @invoice           = attrs["Invoice"] ? Invoice.new(attrs["Invoice"], reference: true) : nil
        @credit_note       = attrs["CreditNote"] ? CreditNote.new(attrs["CreditNote"], reference: true) : nil
        @prepayment        = attrs["Prepayment"] ? Prepayment.new(attrs["Prepayment"], reference: true) : nil
        @overpayment       = attrs["Overpayment"] ? Overpayment.new(attrs["Overpayment"], reference: true) : nil
        @has_account       = attrs["HasAccount"]
      end

      def reference? = @is_reference

      def reconciled? = is_reconciled == true

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(Payment) && other.payment_id == payment_id
      end
      alias eql? ==

      def hash = [self.class, payment_id].hash

      def inspect
        "#<#{self.class} payment_id=#{payment_id.inspect} " \
          "payment_type=#{payment_type.inspect} status=#{status.inspect} amount=#{amount.inspect}>"
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
