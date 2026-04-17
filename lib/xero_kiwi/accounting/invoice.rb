# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a Xero Invoice returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/invoices
    class Invoice
      include Resource

      payload_key "Invoices"
      identity    :invoice_id

      attribute :invoice_id,                      xero: "InvoiceID", type: :guid
      attribute :invoice_number,                  xero: "InvoiceNumber"
      attribute :type,                            xero: "Type",                       type: :enum
      attribute :contact,                         xero: "Contact",                    type: :object, of: Contact, reference: true
      attribute :date,                            xero: "Date",                       type: :date
      attribute :due_date,                        xero: "DueDate",                    type: :date
      attribute :status,                          xero: "Status",                     type: :enum
      attribute :line_amount_types,               xero: "LineAmountTypes"
      attribute :line_items,                      xero: "LineItems",                  type: :collection, of: LineItem
      attribute :sub_total,                       xero: "SubTotal",                   type: :decimal
      attribute :total_tax,                       xero: "TotalTax",                   type: :decimal
      attribute :total,                           xero: "Total",                      type: :decimal
      attribute :total_discount,                  xero: "TotalDiscount",              type: :decimal
      attribute :updated_date_utc,                xero: "UpdatedDateUTC",             type: :date
      attribute :currency_code,                   xero: "CurrencyCode"
      attribute :currency_rate,                   xero: "CurrencyRate", type: :decimal
      attribute :reference,                       xero: "Reference"
      attribute :branding_theme_id,               xero: "BrandingThemeID", type: :guid
      attribute :url,                             xero: "Url"
      attribute :sent_to_contact,                 xero: "SentToContact",              type: :bool
      attribute :expected_payment_date,           xero: "ExpectedPaymentDate",        type: :date
      attribute :planned_payment_date,            xero: "PlannedPaymentDate",         type: :date
      attribute :has_attachments,                 xero: "HasAttachments",             type: :bool
      attribute :repeating_invoice_id,            xero: "RepeatingInvoiceID",         type: :guid
      attribute :payments,                        xero: "Payments",                   type: :collection, of: Payment,     reference: true
      attribute :credit_notes,                    xero: "CreditNotes",                type: :collection, of: CreditNote,  reference: true
      attribute :prepayments,                     xero: "Prepayments",                type: :collection, of: Prepayment,  reference: true
      attribute :overpayments,                    xero: "Overpayments",               type: :collection, of: Overpayment, reference: true
      attribute :amount_due,                      xero: "AmountDue",                  type: :decimal
      attribute :amount_paid,                     xero: "AmountPaid",                 type: :decimal
      attribute :amount_credited,                 xero: "AmountCredited",             type: :decimal
      attribute :cis_deduction,                   xero: "CISDeduction",               type: :decimal
      attribute :fully_paid_on_date,              xero: "FullyPaidOnDate",            type: :date
      attribute :sales_tax_calculation_type_code, xero: "SalesTaxCalculationTypeCode"
      attribute :invoice_addresses,               xero: "InvoiceAddresses", hydrate: ->(raw) { raw || [] }

      def accounts_receivable? = type == "ACCREC"

      def accounts_payable? = type == "ACCPAY"
    end
  end
end
