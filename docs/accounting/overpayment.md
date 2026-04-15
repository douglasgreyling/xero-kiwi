# Overpayments

A Xero **overpayment** is an excess payment received or made beyond the amount
of an invoice. Overpayments are created via the BankTransactions endpoint and
refunded via the Payments endpoint. This resource lets you retrieve overpayments
and their allocations. You need a `tenant_id` from a
[connection](../connections.md) before you can fetch overpayments.

> See: [Xero docs — Overpayments](https://developer.xero.com/documentation/api/accounting/overpayments)

## Listing overpayments

```ruby
client = XeroKiwi::Client.new(access_token: "ya29...")

# Pass a tenant ID string…
overpayments = client.overpayments("70784a63-d24b-46a9-a4db-0e70a274b056")

# …or a XeroKiwi::Connection (its tenant_id is used automatically).
connection = client.connections.first
overpayments = client.overpayments(connection)
```

`client.overpayments` hits `GET /api.xro/2.0/Overpayments` with the
`Xero-Tenant-Id` header set to the tenant you specify. It returns an
`Array<XeroKiwi::Accounting::Overpayment>`.

## Fetching a single overpayment

```ruby
op = client.overpayment(tenant_id, "aea95d78-ea48-456b-9b08-6bc012600072")
op.total  # => "100.00"
```

`client.overpayment` hits `GET /api.xro/2.0/Overpayments/{OverpaymentID}` and
returns a single `XeroKiwi::Accounting::Overpayment`, or `nil` if the response is
empty.

## The Overpayment object

Each `XeroKiwi::Accounting::Overpayment` is an immutable value object exposing the
fields Xero returns:

| Attribute | Type | What it is |
|-----------|------|------------|
| `overpayment_id` | `String` | The unique Xero identifier. |
| `type` | `String` | `"RECEIVE-OVERPAYMENT"` or `"SPEND-OVERPAYMENT"`. |
| `contact` | `XeroKiwi::Accounting::Contact` | The contact (reference — use `contact.reference?` to check). See [Contacts](contact.md). |
| `date` | `Time` | The date the overpayment was made, parsed as UTC. |
| `status` | `String` | e.g. `"AUTHORISED"`, `"PAID"`, `"VOIDED"`. |
| `line_amount_types` | `String` | `"Inclusive"`, `"Exclusive"`, or `"NoTax"`. |
| `line_items` | `Array<XeroKiwi::Accounting::LineItem>` | The line items. See [Prepayments — LineItem](prepayment.md#the-lineitem-object). |
| `sub_total` | `String` | The subtotal excluding taxes. |
| `total_tax` | `String` | The total tax amount. |
| `total` | `String` | The total (subtotal + total tax). |
| `updated_date_utc` | `Time` | When the overpayment was last modified, parsed as UTC. |
| `currency_code` | `String` | The currency code (e.g. `"NZD"`). |
| `currency_rate` | `String` | The currency rate (1.0 for base currency). |
| `remaining_credit` | `String` | The remaining credit balance. |
| `allocations` | `Array<XeroKiwi::Accounting::Allocation>` | Allocations to invoices. Each allocation has an `invoice` reference. |
| `payments` | `Array<XeroKiwi::Accounting::Payment>` | Payment records (references). See [Payments](payment.md). |
| `has_attachments` | `Boolean` | Whether the overpayment has attachments. |
| `reference` | `String` | Reference for the overpayment. |

## Predicates

```ruby
op.receive?  # type == "RECEIVE-OVERPAYMENT"
op.spend?    # type == "SPEND-OVERPAYMENT"
```

## Equality and hashing

Two overpayments are `==` if they share the same `overpayment_id`. `#hash` is
consistent with `==`, so overpayments work as hash keys and in sets.

## Error behaviour

| HTTP status | Exception | What it usually means |
|-------------|-----------|------------------------|
| 200 | (none — returns overpayments) | Success |
| 401 | `XeroKiwi::AuthenticationError` | Access token is invalid or expired |
| 403 | `XeroKiwi::ClientError` | The token doesn't have the required scope |
| 404 | `XeroKiwi::ClientError` | The overpayment ID doesn't exist |

## Common patterns

### Listing overpayments with remaining credit

```ruby
overpayments = client.overpayments(tenant_id)
with_credit = overpayments.select { |op| op.remaining_credit.to_f > 0 }
with_credit.each { |op| puts "#{op.overpayment_id}: #{op.remaining_credit} remaining" }
```
