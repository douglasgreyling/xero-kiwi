# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a Xero Overpayment returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/overpayments
    class Overpayment
      include Resource

      payload_key "Overpayments"
      identity    :overpayment_id

      attribute :overpayment_id,    xero: "OverpaymentID",   type: :guid
      attribute :type,              xero: "Type",            type: :enum
      attribute :contact,           xero: "Contact",         type: :object, of: Contact, reference: true
      attribute :date,              xero: "Date",            type: :date
      attribute :status,            xero: "Status",          type: :enum
      attribute :line_amount_types, xero: "LineAmountTypes"
      attribute :line_items,        xero: "LineItems",       type: :collection, of: LineItem
      attribute :sub_total,         xero: "SubTotal",        type: :decimal
      attribute :total_tax,         xero: "TotalTax",        type: :decimal
      attribute :total,             xero: "Total",           type: :decimal
      attribute :updated_date_utc,  xero: "UpdatedDateUTC",  type: :date
      attribute :currency_code,     xero: "CurrencyCode"
      attribute :currency_rate,     xero: "CurrencyRate",    type: :decimal
      attribute :remaining_credit,  xero: "RemainingCredit", type: :decimal
      attribute :allocations,       xero: "Allocations",     type: :collection, of: "Allocation"
      attribute :payments,          xero: "Payments",        type: :collection, of: "Payment", reference: true
      attribute :has_attachments,   xero: "HasAttachments",  type: :bool
      attribute :reference,         xero: "Reference"

      def receive? = type == "RECEIVE-OVERPAYMENT"

      def spend? = type == "SPEND-OVERPAYMENT"
    end
  end
end
