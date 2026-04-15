# Payments

A Xero **payment** records money received or paid against an invoice, credit
note, prepayment, or overpayment. Payments can be applied to approved AR and AP
invoices, and used to refund credit notes, prepayments, and overpayments. You
need a `tenant_id` from a [connection](../connections.md) before you can fetch
payments.

> See: [Xero docs — Payments](https://developer.xero.com/documentation/api/accounting/payments)

## Listing payments

```ruby
client = XeroKiwi::Client.new(access_token: "ya29...")

# Pass a tenant ID string…
payments = client.payments("70784a63-d24b-46a9-a4db-0e70a274b056")

# …or a XeroKiwi::Connection (its tenant_id is used automatically).
connection = client.connections.first
payments = client.payments(connection)
```

`client.payments` hits `GET /api.xro/2.0/Payments` with the `Xero-Tenant-Id`
header set to the tenant you specify. It returns an
`Array<XeroKiwi::Accounting::Payment>`.

## Fetching a single payment

```ruby
payment = client.payment(tenant_id, "b26fd49a-cbae-470a-a8f8-bcbc119e0379")
payment.amount  # => 500.00
```

`client.payment` hits `GET /api.xro/2.0/Payments/{PaymentID}` and returns a
single `XeroKiwi::Accounting::Payment`, or `nil` if the response is empty.

## The Payment object

Each `XeroKiwi::Accounting::Payment` is an immutable value object exposing the
fields Xero returns:

| Attribute | Type | What it is |
|-----------|------|------------|
| `payment_id` | `String` | The unique Xero identifier. |
| `date` | `Time` | The date the payment was made, parsed as UTC. |
| `currency_rate` | `Numeric` | Exchange rate (1.0 for base currency). |
| `amount` | `Numeric` | The payment amount in the invoice's currency. |
| `bank_amount` | `Numeric` | The payment amount in the account's currency. |
| `reference` | `String` | An optional description for the payment. |
| `is_reconciled` | `Boolean` | Whether the payment has been reconciled. |
| `status` | `String` | e.g. `"AUTHORISED"`, `"DELETED"`. |
| `payment_type` | `String` | e.g. `"ACCRECPAYMENT"`, `"ACCPAYPAYMENT"`. See Xero docs for all types. |
| `updated_date_utc` | `Time` | When the payment was last modified, parsed as UTC. |
| `batch_payment_id` | `String` | The batch payment ID, if created as part of a batch. |
| `batch_payment` | `Hash` | Batch payment details (raw hash). |
| `account` | `Hash` | The account the payment was made from (raw hash with `AccountID`, `Code`, `Name`). |
| `invoice` | `Hash` | The invoice the payment was made against (raw hash). |
| `credit_note` | `Hash` | The credit note being refunded (raw hash), if applicable. |
| `prepayment` | `Hash` | The prepayment being refunded (raw hash), if applicable. |
| `overpayment` | `Hash` | The overpayment being refunded (raw hash), if applicable. |
| `has_account` | `Boolean` | Whether the payment has an associated account. |

## Predicates

```ruby
payment.reconciled?  # is_reconciled == true
```

## Equality and hashing

Two payments are `==` if they share the same `payment_id`. `#hash` is consistent
with `==`, so payments work as hash keys and in sets.

## Error behaviour

| HTTP status | Exception | What it usually means |
|-------------|-----------|------------------------|
| 200 | (none — returns payments) | Success |
| 401 | `XeroKiwi::AuthenticationError` | Access token is invalid or expired |
| 403 | `XeroKiwi::ClientError` | The token doesn't have the required scope |
| 404 | `XeroKiwi::ClientError` | The payment ID doesn't exist |

## Common patterns

### Listing reconciled payments

```ruby
payments = client.payments(tenant_id)
reconciled = payments.select(&:reconciled?)
reconciled.each { |p| puts "#{p.reference}: #{p.amount}" }
```

### Finding payments for a specific invoice

```ruby
payments = client.payments(tenant_id)
for_invoice = payments.select { |p| p.invoice&.dig("InvoiceNumber") == "INV-0001" }
```
