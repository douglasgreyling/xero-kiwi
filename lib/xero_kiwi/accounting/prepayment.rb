# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a Xero Prepayment returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/prepayments
    class Prepayment
      include Resource

      payload_key "Prepayments"
      identity    :prepayment_id

      attribute :prepayment_id,      xero: "PrepaymentID",     type: :guid
      attribute :type,               xero: "Type",             type: :enum, query: true
      attribute :contact,            xero: "Contact",          type: :object, of: Contact, reference: true, query: true
      attribute :date,               xero: "Date",             type: :date, query: true
      attribute :status,             xero: "Status",           type: :enum, query: true
      attribute :line_amount_types,  xero: "LineAmountTypes"
      attribute :line_items,         xero: "LineItems",        type: :collection, of: LineItem
      attribute :sub_total,          xero: "SubTotal",         type: :decimal
      attribute :total_tax,          xero: "TotalTax",         type: :decimal
      attribute :total,              xero: "Total",            type: :decimal
      attribute :updated_date_utc,   xero: "UpdatedDateUTC",   type: :date, query: true
      attribute :currency_code,      xero: "CurrencyCode"
      attribute :currency_rate,      xero: "CurrencyRate", type: :decimal
      attribute :invoice_number,     xero: "InvoiceNumber"
      attribute :remaining_credit,   xero: "RemainingCredit",  type: :decimal
      attribute :allocations,        xero: "Allocations",      type: :collection, of: "Allocation"
      attribute :payments,           xero: "Payments",         type: :collection, of: "Payment", reference: true
      attribute :has_attachments,    xero: "HasAttachments",   type: :bool
      attribute :fully_paid_on_date, xero: "FullyPaidOnDate",  type: :date

      def receive? = type == "RECEIVE-PREPAYMENT"

      def spend? = type == "SPEND-PREPAYMENT"
    end
  end
end
