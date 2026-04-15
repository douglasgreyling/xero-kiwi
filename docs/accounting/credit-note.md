# Credit Notes

A Xero **credit note** is a document that reduces the amount owed on an
invoice. Credit notes can be applied (allocated) to outstanding invoices. You
need a `tenant_id` from a [connection](../connections.md) before you can fetch
credit notes.

> See: [Xero docs — Credit Notes](https://developer.xero.com/documentation/api/accounting/creditnotes)

## Listing credit notes

```ruby
client = XeroKiwi::Client.new(access_token: "ya29...")

# Pass a tenant ID string…
credit_notes = client.credit_notes("70784a63-d24b-46a9-a4db-0e70a274b056")

# …or a XeroKiwi::Connection (its tenant_id is used automatically).
connection = client.connections.first
credit_notes = client.credit_notes(connection)
```

`client.credit_notes` hits `GET /api.xro/2.0/CreditNotes` with the
`Xero-Tenant-Id` header set to the tenant you specify. It returns an
`Array<XeroKiwi::Accounting::CreditNote>`.

## Fetching a single credit note

```ruby
cn = client.credit_note(tenant_id, "aea95d78-ea48-456b-9b08-6bc012600072")
cn.total  # => 100.00
```

`client.credit_note` hits `GET /api.xro/2.0/CreditNotes/{CreditNoteID}` and
returns a single `XeroKiwi::Accounting::CreditNote`, or `nil` if the response is
empty. The single-credit-note response includes full line item details.

## The CreditNote object

Each `XeroKiwi::Accounting::CreditNote` is an immutable value object exposing the
fields Xero returns:

| Attribute | Type | What it is |
|-----------|------|------------|
| `credit_note_id` | `String` | The unique Xero identifier. |
| `credit_note_number` | `String` | The credit note number (e.g. `"CN-0002"`). |
| `type` | `String` | `"ACCRECCREDIT"` (accounts receivable) or `"ACCPAYCREDIT"` (accounts payable). |
| `contact` | `XeroKiwi::Accounting::Contact` | The contact (reference — use `contact.reference?` to check). See [Contacts](contact.md). |
| `date` | `Time` | The date the credit note was issued, parsed as UTC. |
| `status` | `String` | e.g. `"DRAFT"`, `"SUBMITTED"`, `"AUTHORISED"`, `"PAID"`, `"VOIDED"`. |
| `line_amount_types` | `String` | `"Inclusive"`, `"Exclusive"`, or `"NoTax"`. |
| `line_items` | `Array<XeroKiwi::Accounting::LineItem>` | The line items. See [Prepayments — LineItem](prepayment.md#the-lineitem-object). |
| `sub_total` | `Numeric` | The subtotal excluding taxes. |
| `total_tax` | `Numeric` | The total tax amount. |
| `total` | `Numeric` | The total (subtotal + total tax). |
| `cis_deduction` | `Numeric` | CIS deduction (UK Construction Industry Scheme only). |
| `updated_date_utc` | `Time` | When the credit note was last modified, parsed as UTC. |
| `currency_code` | `String` | The currency code (e.g. `"NZD"`). |
| `currency_rate` | `Numeric` | The currency rate (1.0 for base currency). |
| `fully_paid_on_date` | `Time` | When the credit note was fully allocated, parsed as UTC. |
| `reference` | `String` | Additional reference number (ACCRECCREDIT only). |
| `sent_to_contact` | `Boolean` | Whether the credit note has been sent to the contact. |
| `remaining_credit` | `Numeric` | The remaining credit balance. |
| `allocations` | `Array<XeroKiwi::Accounting::Allocation>` | Allocations to invoices. Each allocation has an `invoice` reference. |
| `branding_theme_id` | `String` | The branding theme ID applied to the credit note. |
| `has_attachments` | `Boolean` | Whether the credit note has attachments. |

## Predicates

```ruby
cn.accounts_receivable?  # type == "ACCRECCREDIT"
cn.accounts_payable?     # type == "ACCPAYCREDIT"
```

## Equality and hashing

Two credit notes are `==` if they share the same `credit_note_id`. `#hash` is
consistent with `==`, so credit notes work as hash keys and in sets.

## Error behaviour

| HTTP status | Exception | What it usually means |
|-------------|-----------|------------------------|
| 200 | (none — returns credit notes) | Success |
| 401 | `XeroKiwi::AuthenticationError` | Access token is invalid or expired |
| 403 | `XeroKiwi::ClientError` | The token doesn't have the required scope |
| 404 | `XeroKiwi::ClientError` | The credit note ID doesn't exist |

## Common patterns

### Listing credit notes with remaining credit

```ruby
credit_notes = client.credit_notes(tenant_id)
with_credit = credit_notes.select { |cn| cn.remaining_credit.to_f > 0 }
with_credit.each { |cn| puts "#{cn.credit_note_number}: #{cn.remaining_credit} remaining" }
```
