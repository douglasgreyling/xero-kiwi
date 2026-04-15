# frozen_string_literal: true

require "time"

module XeroKiwi
  module Accounting
    # Represents a Xero Invoice returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/invoices
    class Invoice
      ATTRIBUTES = {
        invoice_id:                      "InvoiceID",
        invoice_number:                  "InvoiceNumber",
        type:                            "Type",
        contact:                         "Contact",
        date:                            "Date",
        due_date:                        "DueDate",
        status:                          "Status",
        line_amount_types:               "LineAmountTypes",
        line_items:                      "LineItems",
        sub_total:                       "SubTotal",
        total_tax:                       "TotalTax",
        total:                           "Total",
        total_discount:                  "TotalDiscount",
        updated_date_utc:                "UpdatedDateUTC",
        currency_code:                   "CurrencyCode",
        currency_rate:                   "CurrencyRate",
        reference:                       "Reference",
        branding_theme_id:               "BrandingThemeID",
        url:                             "Url",
        sent_to_contact:                 "SentToContact",
        expected_payment_date:           "ExpectedPaymentDate",
        planned_payment_date:            "PlannedPaymentDate",
        has_attachments:                 "HasAttachments",
        repeating_invoice_id:            "RepeatingInvoiceID",
        payments:                        "Payments",
        credit_notes:                    "CreditNotes",
        prepayments:                     "Prepayments",
        overpayments:                    "Overpayments",
        amount_due:                      "AmountDue",
        amount_paid:                     "AmountPaid",
        amount_credited:                 "AmountCredited",
        cis_deduction:                   "CISDeduction",
        fully_paid_on_date:              "FullyPaidOnDate",
        sales_tax_calculation_type_code: "SalesTaxCalculationTypeCode",
        invoice_addresses:               "InvoiceAddresses"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def self.from_response(payload)
        return [] if payload.nil?

        items = payload["Invoices"]
        return [] if items.nil?

        items.map { |attrs| new(attrs) }
      end

      def initialize(attrs, reference: false) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
        attrs                            = attrs.transform_keys(&:to_s)
        @is_reference                    = reference
        @invoice_id                      = attrs["InvoiceID"]
        @invoice_number                  = attrs["InvoiceNumber"]
        @type                            = attrs["Type"]
        @contact                         = attrs["Contact"] ? Contact.new(attrs["Contact"], reference: true) : nil
        @date                            = parse_time(attrs["Date"])
        @due_date                        = parse_time(attrs["DueDate"])
        @status                          = attrs["Status"]
        @line_amount_types               = attrs["LineAmountTypes"]
        @line_items                      = (attrs["LineItems"] || []).map { |li| LineItem.new(li) }
        @sub_total                       = attrs["SubTotal"]
        @total_tax                       = attrs["TotalTax"]
        @total                           = attrs["Total"]
        @total_discount                  = attrs["TotalDiscount"]
        @updated_date_utc                = parse_time(attrs["UpdatedDateUTC"])
        @currency_code                   = attrs["CurrencyCode"]
        @currency_rate                   = attrs["CurrencyRate"]
        @reference                       = attrs["Reference"]
        @branding_theme_id               = attrs["BrandingThemeID"]
        @url                             = attrs["Url"]
        @sent_to_contact                 = attrs["SentToContact"]
        @expected_payment_date           = parse_time(attrs["ExpectedPaymentDate"])
        @planned_payment_date            = parse_time(attrs["PlannedPaymentDate"])
        @has_attachments                 = attrs["HasAttachments"]
        @repeating_invoice_id            = attrs["RepeatingInvoiceID"]
        @payments                        = (attrs["Payments"] || []).map { |p| Payment.new(p, reference: true) }
        @credit_notes                    = (attrs["CreditNotes"] || []).map { |cn| CreditNote.new(cn, reference: true) }
        @prepayments                     = (attrs["Prepayments"] || []).map { |p| Prepayment.new(p, reference: true) }
        @overpayments                    = (attrs["Overpayments"] || []).map { |o| Overpayment.new(o, reference: true) }
        @amount_due                      = attrs["AmountDue"]
        @amount_paid                     = attrs["AmountPaid"]
        @amount_credited                 = attrs["AmountCredited"]
        @cis_deduction                   = attrs["CISDeduction"]
        @fully_paid_on_date              = parse_time(attrs["FullyPaidOnDate"])
        @sales_tax_calculation_type_code = attrs["SalesTaxCalculationTypeCode"]
        @invoice_addresses               = attrs["InvoiceAddresses"] || []
      end

      def reference? = @is_reference

      def accounts_receivable? = type == "ACCREC"

      def accounts_payable? = type == "ACCPAY"

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(Invoice) && other.invoice_id == invoice_id
      end
      alias eql? ==

      def hash = [self.class, invoice_id].hash

      def inspect
        "#<#{self.class} invoice_id=#{invoice_id.inspect} " \
          "invoice_number=#{invoice_number.inspect} type=#{type.inspect} " \
          "status=#{status.inspect} total=#{total.inspect}>"
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
