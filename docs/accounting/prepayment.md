# Prepayments

A Xero **prepayment** is a payment received or made in advance of an invoice.
Prepayments are created via the BankTransactions endpoint and refunded via the
Payments endpoint. This resource lets you retrieve prepayments and their
allocations. You need a `tenant_id` from a [connection](../connections.md)
before you can fetch prepayments.

> See: [Xero docs — Prepayments](https://developer.xero.com/documentation/api/accounting/prepayments)

## Listing prepayments

```ruby
client = XeroKiwi::Client.new(access_token: "ya29...")

# Pass a tenant ID string…
prepayments = client.prepayments("70784a63-d24b-46a9-a4db-0e70a274b056")

# …or a XeroKiwi::Connection (its tenant_id is used automatically).
connection = client.connections.first
prepayments = client.prepayments(connection)
```

`client.prepayments` hits `GET /api.xro/2.0/Prepayments` with the
`Xero-Tenant-Id` header set to the tenant you specify. It returns an
`Array<XeroKiwi::Accounting::Prepayment>`.

## Fetching a single prepayment

```ruby
prepayment = client.prepayment(tenant_id, "aea95d78-ea48-456b-9b08-6bc012600072")
prepayment.total  # => "100.00"
```

`client.prepayment` hits `GET /api.xro/2.0/Prepayments/{PrepaymentID}` and
returns a single `XeroKiwi::Accounting::Prepayment`, or `nil` if the response is
empty.

## The Prepayment object

Each `XeroKiwi::Accounting::Prepayment` is an immutable value object exposing the
fields Xero returns:

| Attribute | Type | What it is |
|-----------|------|------------|
| `prepayment_id` | `String` | The unique Xero identifier. |
| `type` | `String` | `"RECEIVE-PREPAYMENT"` or `"SPEND-PREPAYMENT"`. |
| `contact` | `XeroKiwi::Accounting::Contact` | The contact (reference — use `contact.reference?` to check). See [Contacts](contact.md). |
| `date` | `Time` | The date the prepayment was created, parsed as UTC. |
| `status` | `String` | e.g. `"AUTHORISED"`, `"PAID"`, `"VOIDED"`. |
| `line_amount_types` | `String` | `"Inclusive"`, `"Exclusive"`, or `"NoTax"`. |
| `line_items` | `Array<XeroKiwi::Accounting::LineItem>` | The line items. See [LineItem](#the-lineitem-object). |
| `sub_total` | `String` | The subtotal excluding taxes. |
| `total_tax` | `String` | The total tax amount. |
| `total` | `String` | The total (subtotal + total tax). |
| `updated_date_utc` | `Time` | When the prepayment was last modified, parsed as UTC. |
| `currency_code` | `String` | The currency code (e.g. `"NZD"`). |
| `currency_rate` | `String` | The currency rate (1.0 for base currency). |
| `invoice_number` | `String` | The invoice number (for receive prepayments only). |
| `remaining_credit` | `String` | The remaining credit balance. |
| `allocations` | `Array<XeroKiwi::Accounting::Allocation>` | Allocations to invoices. Each allocation has an `invoice` reference. |
| `payments` | `Array<XeroKiwi::Accounting::Payment>` | Payment records (references). See [Payments](payment.md). |
| `has_attachments` | `Boolean` | Whether the prepayment has attachments. |
| `fully_paid_on_date` | `Time` | When the prepayment was fully allocated, parsed as UTC. |

## The LineItem object

Each `XeroKiwi::Accounting::LineItem` is an immutable value object shared across
documents (prepayments, invoices, etc.):

| Attribute | Type | What it is |
|-----------|------|------------|
| `description` | `String` | Line item description. |
| `quantity` | `Float` | Quantity. |
| `unit_amount` | `Float` | Unit amount. |
| `account_code` | `String` | The account code. |
| `tax_type` | `String` | The tax type override. |
| `tax_amount` | `Float` | The calculated tax amount. |
| `line_amount` | `Float` | The line total. |
| `tracking` | `Array<Hash>` | Tracking categories (raw, max 2 per line). |

## Predicates

```ruby
prepayment.receive?  # type == "RECEIVE-PREPAYMENT"
prepayment.spend?    # type == "SPEND-PREPAYMENT"
```

## Equality and hashing

Two prepayments are `==` if they share the same `prepayment_id`. `#hash` is
consistent with `==`, so prepayments work as hash keys and in sets.

## Error behaviour

| HTTP status | Exception | What it usually means |
|-------------|-----------|------------------------|
| 200 | (none — returns prepayments) | Success |
| 401 | `XeroKiwi::AuthenticationError` | Access token is invalid or expired |
| 403 | `XeroKiwi::ClientError` | The token doesn't have the required scope |
| 404 | `XeroKiwi::ClientError` | The prepayment ID doesn't exist |

## Common patterns

### Listing prepayments with remaining credit

```ruby
prepayments = client.prepayments(tenant_id)
with_credit = prepayments.select { |p| p.remaining_credit.to_f > 0 }
with_credit.each { |p| puts "#{p.prepayment_id}: #{p.remaining_credit} remaining" }
```
