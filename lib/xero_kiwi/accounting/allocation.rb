# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents an allocation of a credit note, prepayment, or overpayment
    # against an invoice.
    #
    # See: https://developer.xero.com/documentation/api/accounting/overpayments
    class Allocation
      include Resource

      identity :allocation_id

      attribute :allocation_id, xero: "AllocationID", type: :guid
      attribute :amount,        xero: "Amount",       type: :decimal
      attribute :date,          xero: "Date",         type: :date
      attribute :invoice,       xero: "Invoice",      type: :object, of: Invoice, reference: true
      attribute :is_deleted,    xero: "IsDeleted",    type: :bool
    end
  end
end
