# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents an allocation of a credit note, prepayment, or overpayment
    # against an invoice.
    #
    # THE ALLOCATED VALUE ARRIVES UNDER DIFFERENT KEYS IN DIFFERENT XERO
    # REPRESENTATIONS, and getting it wrong writes zeroes into money:
    #
    #   JSON (what this client requests):  "Amount"
    #   XML  (what other clients get):     "AppliedAmount"
    #
    # That is not a request-vs-response split, which is what 0.6.0 assumed
    # when it renamed `amount` to `applied_amount` — an assumption drawn from
    # payloads a legacy XML client had stored, and wrong for this JSON-only
    # client. Both keys are modelled now, and `#amount` and `#applied_amount`
    # each resolve to whichever one Xero populated, so neither can be nil
    # when the other holds a value. This has been got wrong twice in opposite
    # directions; reading both is cheaper than being certain.
    #
    # See: https://developer.xero.com/documentation/api/accounting/overpayments
    class Allocation
      include Resource

      identity :allocation_id

      attribute :allocation_id,  xero: "AllocationID",  type: :guid
      attribute :amount,         xero: "Amount",        type: :decimal
      attribute :applied_amount, xero: "AppliedAmount", type: :decimal
      attribute :date,           xero: "Date",          type: :date
      attribute :invoice,        xero: "Invoice",       type: :object, of: Invoice, reference: true
      attribute :is_deleted,     xero: "IsDeleted",     type: :bool

      # Both names are public API and both resolve to the same value. `to_h`
      # therefore reports it under both keys; `raw` still shows exactly which
      # one Xero sent.
      def amount = @amount.nil? ? @applied_amount : @amount

      def applied_amount = @applied_amount.nil? ? @amount : @applied_amount
    end
  end
end
