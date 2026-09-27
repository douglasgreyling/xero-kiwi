# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents an allocation of a credit note, prepayment, or overpayment
    # against an invoice.
    #
    # Xero names the allocated value differently depending on direction: the
    # allocation *request* body takes "Amount", while every *response* — and
    # allocations only ever reach this gem embedded in a CreditNote,
    # Prepayment or Overpayment response — carries "AppliedAmount". This
    # class was originally modelled off the request shape, so `amount`
    # silently returned nil for every allocation the gem could actually
    # produce. `#amount` is now an alias of `#applied_amount` so callers who
    # reached for the obvious name get the value they meant.
    #
    # See: https://developer.xero.com/documentation/api/accounting/overpayments
    class Allocation
      include Resource

      identity :allocation_id

      attribute :allocation_id,  xero: "AllocationID",  type: :guid
      attribute :applied_amount, xero: "AppliedAmount", type: :decimal
      attribute :date,           xero: "Date",          type: :date
      attribute :invoice,        xero: "Invoice",       type: :object, of: Invoice, reference: true
      attribute :is_deleted,     xero: "IsDeleted",     type: :bool

      # Kept for callers written against the pre-0.6.0 attribute name. It
      # could only ever have returned nil, so nothing that relied on a real
      # value is affected.
      def amount = applied_amount
    end
  end
end
