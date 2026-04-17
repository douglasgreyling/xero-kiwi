# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a Xero Credit Note returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/creditnotes
    class CreditNote
      include Resource

      payload_key "CreditNotes"
      identity    :credit_note_id

      attribute :credit_note_id,     xero: "CreditNoteID", type: :guid
      attribute :credit_note_number, xero: "CreditNoteNumber"
      attribute :type,               xero: "Type",             type: :enum
      attribute :contact,            xero: "Contact",          type: :object, of: Contact, reference: true
      attribute :date,               xero: "Date",             type: :date
      attribute :status,             xero: "Status",           type: :enum
      attribute :line_amount_types,  xero: "LineAmountTypes"
      attribute :line_items,         xero: "LineItems",        type: :collection, of: LineItem
      attribute :sub_total,          xero: "SubTotal",         type: :decimal
      attribute :total_tax,          xero: "TotalTax",         type: :decimal
      attribute :total,              xero: "Total",            type: :decimal
      attribute :cis_deduction,      xero: "CISDeduction",     type: :decimal
      attribute :updated_date_utc,   xero: "UpdatedDateUTC",   type: :date
      attribute :currency_code,      xero: "CurrencyCode"
      attribute :currency_rate,      xero: "CurrencyRate",     type: :decimal
      attribute :fully_paid_on_date, xero: "FullyPaidOnDate",  type: :date
      attribute :reference,          xero: "Reference"
      attribute :sent_to_contact,    xero: "SentToContact",    type: :bool
      attribute :remaining_credit,   xero: "RemainingCredit",  type: :decimal
      attribute :allocations,        xero: "Allocations",      type: :collection, of: "Allocation"
      attribute :branding_theme_id,  xero: "BrandingThemeID",  type: :guid
      attribute :has_attachments,    xero: "HasAttachments",   type: :bool

      def accounts_receivable? = type == "ACCRECCREDIT"

      def accounts_payable? = type == "ACCPAYCREDIT"
    end
  end
end
