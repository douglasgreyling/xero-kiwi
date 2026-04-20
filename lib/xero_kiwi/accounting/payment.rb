# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a Xero Payment returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/payments
    class Payment
      include Resource

      payload_key "Payments"
      identity    :payment_id

      attribute :payment_id,       xero: "PaymentID",       type: :guid
      attribute :date,             xero: "Date",            type: :date, query: true
      attribute :currency_rate,    xero: "CurrencyRate",    type: :decimal
      attribute :amount,           xero: "Amount",          type: :decimal
      attribute :bank_amount,      xero: "BankAmount",      type: :decimal
      attribute :reference,        xero: "Reference",       query: true
      attribute :is_reconciled,    xero: "IsReconciled",    type: :bool
      attribute :status,           xero: "Status",          type: :enum, query: true
      attribute :payment_type,     xero: "PaymentType",     type: :enum, query: true
      attribute :updated_date_utc, xero: "UpdatedDateUTC",  type: :date, query: true
      attribute :batch_payment_id, xero: "BatchPaymentID",  type: :guid
      attribute :batch_payment,    xero: "BatchPayment"
      attribute :account,          xero: "Account"
      attribute :invoice,          xero: "Invoice",         type: :object, of: "Invoice",    reference: true, query: true
      attribute :credit_note,      xero: "CreditNote",      type: :object, of: CreditNote,   reference: true
      attribute :prepayment,       xero: "Prepayment",      type: :object, of: Prepayment,   reference: true
      attribute :overpayment,      xero: "Overpayment",     type: :object, of: Overpayment,  reference: true
      attribute :has_account,      xero: "HasAccount",      type: :bool

      def reconciled? = is_reconciled == true
    end
  end
end
