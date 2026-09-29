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
prepayment.total  # => BigDecimal("100.00")
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
| `sub_total` | `BigDecimal` | The subtotal excluding taxes. |
| `total_tax` | `BigDecimal` | The total tax amount. |
| `total` | `BigDecimal` | The total (subtotal + total tax). |
| `applied_amount` | `BigDecimal` | Only set when this prepayment is nested under an invoice, where it is the amount applied to *that* invoice — not the prepayment total. `nil` on a prepayment fetched in its own right. See [Nested under an invoice](#nested-under-an-invoice). |
| `updated_date_utc` | `Time` | When the prepayment was last modified, parsed as UTC. |
| `currency_code` | `String` | The currency code (e.g. `"NZD"`). |
| `currency_rate` | `BigDecimal` | The currency rate (1.0 for base currency). |
| `invoice_number` | `String` | The invoice number (for receive prepayments only). |
| `reference` | `String` | The prepayment reference, as on credit notes and overpayments. Nil when Xero sends it empty. |
| `remaining_credit` | `BigDecimal` | The remaining credit balance. |
| `allocations` | `Array<XeroKiwi::Accounting::Allocation>` | Allocations to invoices. Each has `allocation_id`, the allocated value (as both `amount` and `applied_amount` — see below), `date`, `is_deleted`, and an `invoice` reference. |
| `payments` | `Array<XeroKiwi::Accounting::Payment>` | Payment records (references). See [Payments](payment.md). |
| `branding_theme_id` | `String` | The branding theme applied, as on credit notes and invoices. |
| `has_attachments` | `Boolean` | Whether the prepayment has attachments. |
| `fully_paid_on_date` | `Time` | When the prepayment was fully allocated, parsed as UTC. |

## The LineItem object

Each `XeroKiwi::Accounting::LineItem` is an immutable value object shared across
documents (prepayments, invoices, etc.):

| Attribute | Type | What it is |
|-----------|------|------------|
| `description` | `String` | Line item description. |
| `quantity` | `BigDecimal` | Quantity. |
| `unit_amount` | `BigDecimal` | Unit amount. |
| `account_code` | `String` | The account code. |
| `account_id` | `String` | The account ID. Xero sends this as `AccountID`; kiwi read `AccountId` until 0.10.0 and so returned `nil`. |
| `tax_type` | `String` | The tax type override. |
| `tax_amount` | `BigDecimal` | The calculated tax amount. |
| `line_amount` | `BigDecimal` | The line total. |
| `tracking` | `Array<Hash>` | Tracking categories (raw, max 2 per line). |

## Nested under an invoice

`invoice.prepayments` does not return whole prepayments. Xero nests an
**allocation stub** there — a partial prepayment describing how much of it
was applied to *that* invoice:

```ruby
invoice = client.invoices(tenant_id).first
stub    = invoice.prepayments.find { |s| s.applied_amount != s.total }

stub.applied_amount  # => BigDecimal("999.99")   applied to this invoice
stub.total           # => BigDecimal("1784.87")  the prepayment's own total
stub.prepayment_id   # => "4a27d582-…"           fetch it in full with this
```

`applied_amount` and `total` answer different questions, and they differ on
7 of the 9 stubs in this gem's recorded response. Reaching for `total`
to ask "how much was applied to this invoice" overstates it.

A stub carries only `prepayment_id`, `applied_amount`, `total` and `date`.
Everything else is `nil` or empty, including `line_items` — fetch the
prepayment by its ID when you need the rest of it.

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
