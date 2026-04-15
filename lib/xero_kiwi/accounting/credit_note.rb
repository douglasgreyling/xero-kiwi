# frozen_string_literal: true

require "time"

module XeroKiwi
  module Accounting
    # Represents a Xero Credit Note returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/creditnotes
    class CreditNote
      ATTRIBUTES = {
        credit_note_id:     "CreditNoteID",
        credit_note_number: "CreditNoteNumber",
        type:               "Type",
        contact:            "Contact",
        date:               "Date",
        status:             "Status",
        line_amount_types:  "LineAmountTypes",
        line_items:         "LineItems",
        sub_total:          "SubTotal",
        total_tax:          "TotalTax",
        total:              "Total",
        cis_deduction:      "CISDeduction",
        updated_date_utc:   "UpdatedDateUTC",
        currency_code:      "CurrencyCode",
        currency_rate:      "CurrencyRate",
        fully_paid_on_date: "FullyPaidOnDate",
        reference:          "Reference",
        sent_to_contact:    "SentToContact",
        remaining_credit:   "RemainingCredit",
        allocations:        "Allocations",
        branding_theme_id:  "BrandingThemeID",
        has_attachments:    "HasAttachments"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def self.from_response(payload)
        return [] if payload.nil?

        items = payload["CreditNotes"]
        return [] if items.nil?

        items.map { |attrs| new(attrs) }
      end

      def initialize(attrs, reference: false) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        attrs                = attrs.transform_keys(&:to_s)
        @is_reference        = reference
        @credit_note_id      = attrs["CreditNoteID"]
        @credit_note_number  = attrs["CreditNoteNumber"]
        @type                = attrs["Type"]
        @contact             = attrs["Contact"] ? Contact.new(attrs["Contact"], reference: true) : nil
        @date                = parse_time(attrs["Date"])
        @status              = attrs["Status"]
        @line_amount_types   = attrs["LineAmountTypes"]
        @line_items          = (attrs["LineItems"] || []).map { |li| LineItem.new(li) }
        @sub_total           = attrs["SubTotal"]
        @total_tax           = attrs["TotalTax"]
        @total               = attrs["Total"]
        @cis_deduction       = attrs["CISDeduction"]
        @updated_date_utc    = parse_time(attrs["UpdatedDateUTC"])
        @currency_code       = attrs["CurrencyCode"]
        @currency_rate       = attrs["CurrencyRate"]
        @fully_paid_on_date  = parse_time(attrs["FullyPaidOnDate"])
        @reference           = attrs["Reference"]
        @sent_to_contact     = attrs["SentToContact"]
        @remaining_credit    = attrs["RemainingCredit"]
        @allocations         = (attrs["Allocations"] || []).map { |a| Allocation.new(a) }
        @branding_theme_id   = attrs["BrandingThemeID"]
        @has_attachments     = attrs["HasAttachments"]
      end

      def accounts_receivable? = type == "ACCRECCREDIT"

      def reference? = @is_reference

      def accounts_payable? = type == "ACCPAYCREDIT"

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(CreditNote) && other.credit_note_id == credit_note_id
      end
      alias eql? ==

      def hash = [self.class, credit_note_id].hash

      def inspect
        "#<#{self.class} credit_note_id=#{credit_note_id.inspect} " \
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
