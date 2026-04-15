# Invoices

A Xero **invoice** is either a sales invoice (accounts receivable, `ACCREC`) or
a purchase bill (accounts payable, `ACCPAY`). Invoices carry line items,
payments, credit notes, and allocation details. You need a `tenant_id` from a
[connection](../connections.md) before you can fetch invoices.

> See: [Xero docs — Invoices](https://developer.xero.com/documentation/api/accounting/invoices)

## Listing invoices

```ruby
client = XeroKiwi::Client.new(access_token: "ya29...")

# Pass a tenant ID string…
invoices = client.invoices("70784a63-d24b-46a9-a4db-0e70a274b056")

# …or a XeroKiwi::Connection (its tenant_id is used automatically).
connection = client.connections.first
invoices = client.invoices(connection)
```

`client.invoices` hits `GET /api.xro/2.0/Invoices` with the `Xero-Tenant-Id`
header set to the tenant you specify. It returns an
`Array<XeroKiwi::Accounting::Invoice>`.

**Note:** The list response returns only a summary of each contact and no line
items. Fetch an individual invoice for full details including line items.

## Fetching a single invoice

```ruby
inv = client.invoice(tenant_id, "243216c5-369e-4056-ac67-05388f86dc81")
inv.total           # => "2025.00"
inv.invoice_number  # => "OIT00546"
```

`client.invoice` hits `GET /api.xro/2.0/Invoices/{InvoiceID}` and returns a
single `XeroKiwi::Accounting::Invoice`, or `nil` if the response is empty.

## The Invoice object

Each `XeroKiwi::Accounting::Invoice` is an immutable value object. The fields below
cover both the list and single-invoice responses:

| Attribute | Type | What it is |
|-----------|------|------------|
| `invoice_id` | `String` | The unique Xero identifier. |
| `invoice_number` | `String` | The invoice number (e.g. `"OIT00546"`). |
| `type` | `String` | `"ACCREC"` (sales) or `"ACCPAY"` (bills). |
| `contact` | `XeroKiwi::Accounting::Contact` | The contact (reference — use `contact.reference?` to check). See [Contacts](contact.md). |
| `date` | `Time` | The invoice date, parsed as UTC. |
| `due_date` | `Time` | The due date, parsed as UTC. |
| `status` | `String` | e.g. `"DRAFT"`, `"SUBMITTED"`, `"AUTHORISED"`, `"PAID"`, `"VOIDED"`, `"DELETED"`. |
| `line_amount_types` | `String` | `"Inclusive"`, `"Exclusive"`, or `"NoTax"`. |
| `line_items` | `Array<XeroKiwi::Accounting::LineItem>` | The line items (empty on list, populated on single). See [Prepayments — LineItem](prepayment.md#the-lineitem-object). |
| `sub_total` | `String/Numeric` | The subtotal excluding taxes. |
| `total_tax` | `String/Numeric` | The total tax amount. |
| `total` | `String/Numeric` | The total (subtotal + total tax). |
| `total_discount` | `String/Numeric` | Total discounts on line items. |
| `updated_date_utc` | `Time` | When the invoice was last modified, parsed as UTC. |
| `currency_code` | `String` | The currency code (e.g. `"NZD"`). |
| `currency_rate` | `Numeric` | The currency rate (1.0 for base currency). |
| `reference` | `String` | Additional reference number (ACCREC only). |
| `branding_theme_id` | `String` | The branding theme ID. |
| `url` | `String` | URL link to a source document. |
| `sent_to_contact` | `Boolean` | Whether the invoice displays as "sent" in Xero. |
| `expected_payment_date` | `Time` | Expected payment date (ACCREC only). |
| `planned_payment_date` | `Time` | Planned payment date (ACCPAY only). |
| `has_attachments` | `Boolean` | Whether the invoice has attachments. |
| `repeating_invoice_id` | `String` | The repeating invoice template ID, if applicable. |
| `payments` | `Array<XeroKiwi::Accounting::Payment>` | Payment records (references). See [Payments](payment.md). |
| `credit_notes` | `Array<Hash>` | Credit notes applied (raw hashes). |
| `prepayments` | `Array<Hash>` | Prepayments applied (raw hashes). |
| `overpayments` | `Array<Hash>` | Overpayments applied (raw hashes). |
| `amount_due` | `String/Numeric` | Amount remaining to be paid. |
| `amount_paid` | `String/Numeric` | Sum of payments received. |
| `amount_credited` | `String/Numeric` | Sum of credit notes, overpayments, and prepayments applied. |
| `cis_deduction` | `Numeric` | CIS deduction (UK Construction Industry Scheme only). |
| `fully_paid_on_date` | `Time` | When the invoice was fully paid, parsed as UTC. |
| `sales_tax_calculation_type_code` | `String` | US auto sales tax calculation type. |
| `invoice_addresses` | `Array<Hash>` | Invoice addresses (US auto sales tax only). |

## Predicates

```ruby
inv.accounts_receivable?  # type == "ACCREC"
inv.accounts_payable?     # type == "ACCPAY"
```

## Equality and hashing

Two invoices are `==` if they share the same `invoice_id`. `#hash` is consistent
with `==`, so invoices work as hash keys and in sets.

## Error behaviour

| HTTP status | Exception | What it usually means |
|-------------|-----------|------------------------|
| 200 | (none — returns invoices) | Success |
| 401 | `XeroKiwi::AuthenticationError` | Access token is invalid or expired |
| 403 | `XeroKiwi::ClientError` | The token doesn't have the required scope |
| 404 | `XeroKiwi::ClientError` | The invoice ID doesn't exist |

## Common patterns

### Retrieving the online invoice URL

For sales (ACCREC) invoices that are not in DRAFT status, you can retrieve the
online invoice URL that customers can use to view and pay:

```ruby
url = client.online_invoice_url(tenant_id, "243216c5-369e-4056-ac67-05388f86dc81")
puts url  # => "https://in.xero.com/iztKMjyAEJT7MVnmruxgCdIJUDStfRgmtdQSIW13"
```

Returns `nil` if no online invoice URL is available.

### Listing outstanding invoices

```ruby
invoices = client.invoices(tenant_id)
outstanding = invoices.select { |inv| inv.amount_due.to_f > 0 }
outstanding.each { |inv| puts "#{inv.invoice_number}: #{inv.amount_due} due" }
```

### Fetching an invoice with full line items

```ruby
inv = client.invoice(tenant_id, "243216c5-369e-4056-ac67-05388f86dc81")
inv.line_items.each do |li|
  puts "  #{li.description}: #{li.line_amount}"
end
```
