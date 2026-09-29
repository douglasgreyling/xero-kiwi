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
| `sub_total` | `BigDecimal` | The subtotal excluding taxes. |
| `total_tax` | `BigDecimal` | The total tax amount. |
| `total` | `BigDecimal` | The total (subtotal + total tax). |
| `applied_amount` | `BigDecimal` | Only set when this credit note is nested under an invoice, where it is the amount applied to *that* invoice — not the credit note total. `nil` on a credit note fetched in its own right. See [Nested under an invoice](#nested-under-an-invoice). |
| `cis_deduction` | `BigDecimal` | CIS deduction (UK Construction Industry Scheme only). |
| `updated_date_utc` | `Time` | When the credit note was last modified, parsed as UTC. |
| `currency_code` | `String` | The currency code (e.g. `"NZD"`). |
| `currency_rate` | `BigDecimal` | The currency rate (1.0 for base currency). |
| `fully_paid_on_date` | `Time` | When the credit note was fully allocated, parsed as UTC. |
| `reference` | `String` | Additional reference number (ACCRECCREDIT only). |
| `sent_to_contact` | `Boolean` | Whether the credit note has been sent to the contact. |
| `remaining_credit` | `BigDecimal` | The remaining credit balance. |
| `allocations` | `Array<XeroKiwi::Accounting::Allocation>` | Allocations to invoices. Each has `allocation_id`, the allocated value (as both `amount` and `applied_amount` — see below), `date`, `is_deleted`, and an `invoice` reference. |
| `payments` | `Array<XeroKiwi::Accounting::Payment>` | Payment records (references), as on prepayments and overpayments. See [Payments](payment.md). |
| `branding_theme_id` | `String` | The branding theme ID applied to the credit note. |
| `has_errors` | `Boolean` | Whether Xero flagged validation errors on the credit note. |
| `invoice_addresses` | `Array<Hash>` | Invoice addresses (US auto sales tax only). Empty array when absent. |
| `has_attachments` | `Boolean` | Whether the credit note has attachments. |

## Nested under an invoice

`invoice.credit_notes` does not return whole credit notes. Xero nests an
**allocation stub** there — a partial credit note describing how much of it
was applied to *that* invoice:

```ruby
invoice = client.invoices(tenant_id).first
stub    = invoice.credit_notes.find { |s| s.applied_amount != s.total }

stub.applied_amount  # => BigDecimal("857.35")    applied to this invoice
stub.total           # => BigDecimal("10983.65")  the credit note's own total
stub.credit_note_id  # => "4bbdbaaf-…"            fetch it in full with this
```

`applied_amount` and `total` answer different questions, and they differ on
8 of the 11 stubs in this gem's recorded response. Reaching for `total`
to ask "how much was applied to this invoice" overstates it.

A stub carries only `credit_note_id`, `applied_amount`, `total` and `date`.
Everything else is `nil` or empty, including `line_items` — fetch the
credit note by its ID when you need the rest of it.

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

## The allocated value: `amount` and `applied_amount`

Xero sends the allocated value under **different keys in different
representations**:

| Representation | Key |
|---|---|
| JSON — what this client requests | `Amount` |
| XML — what other Xero clients get | `AppliedAmount` |

Kiwi models both and both readers resolve to whichever one arrived, so
`allocation.amount` and `allocation.applied_amount` return the same value and
neither is nil while the other holds one. `to_h` reports it under both keys;
`raw` shows which key Xero actually sent.

This is worth knowing if you are migrating from a client that spoke XML and
have stored payloads: your old rows say `AppliedAmount` and Xero's JSON says
`Amount`, for the same field on the same record. Key names do not reliably
carry across the two representations — an assumption that has produced two
separate silent-nil bugs here, each one an importer writing `0.0` into every
allocated amount with nothing raising.
