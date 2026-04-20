# Querying

Every accounting list endpoint supports four optional query-time features:

- **`where:`** — filter expressions
- **`order:`** — sorting
- **`page:`** — pagination
- **`modified_since:`** — conditional GET via `If-Modified-Side` header

```ruby
page = client.invoices(
  tenant,
  where: { status: "AUTHORISED", date: Date.new(2026, 1, 1)..Date.new(2026, 4, 1) },
  order: { date: :desc },
  page:  1
)

page.size          # => 100
page.page          # => 1
page.page_size     # => 100
page.each { |invoice| … }
```

## Return type: `XeroKiwi::Page`

List methods return a `XeroKiwi::Page` — an `Enumerable`-backed wrapper
exposing items plus pagination metadata:

```ruby
page = client.invoices(tenant)

page.each   { |inv| … }   # Enumerable
page.map    { |inv| … }   # Enumerable
page.first                # first item
page.size                 # 100
page.empty?               # false
page.to_a                 # raw Array

page.page         # which page number was returned
page.page_size    # how many items per page (Xero's default is 100)
page.item_count   # how many items are on this page
page.total_count  # total item count across all pages (when Xero reports it)
```

Because `Page` includes `Enumerable` plus `size` / `empty?` / `to_a`, the
common idioms (`.map`, `.select`, `.first`, `.count`) keep working. Callers
that need raw `Array` behaviour (`<<`, slicing, `JSON.dump`,
`is_a?(Array)`) call `.to_a`.

## `where:` — filtering

Two shapes are supported.

### Hash (recommended)

Kiwi owns the quoting and literal syntax. Field names are the snake-case
Ruby attribute names.

```ruby
client.invoices(tenant, where: { status: "AUTHORISED" })
# emits: Status=="AUTHORISED"

client.invoices(tenant, where: { status: "AUTHORISED", type: "ACCREC" })
# joined with &&

client.invoices(tenant, where: { status: %w[AUTHORISED DRAFT] })
# Array value → IN-semantics: (Status=="AUTHORISED" || Status=="DRAFT")

client.invoices(tenant, where: { date: Date.new(2026, 1, 1)..Date.new(2026, 4, 1) })
# Range value → Date>=DateTime(2026,1,1) && Date<=DateTime(2026,4,1)

client.invoices(tenant, where: { contact: { contact_id: "abc-123" } })
# Hash value on a nested object → Contact.ContactID==Guid("abc-123")
```

Literal formatting per field type (declared in the resource class):

| Type       | Rendered as               |
|------------|---------------------------|
| `:guid`    | `Guid("…")`               |
| `:date`    | `DateTime(y,m,d)` in UTC  |
| `:string`  | `"…"` (escaped)           |
| `:enum`    | `"…"` (escaped)           |
| `:bool`    | `true` / `false`          |
| `:decimal` | `99.5`                    |

Unknown field names raise `ArgumentError` so typos surface at the call
site rather than producing broken Xero queries.

### Raw String (escape hatch)

When the hash form can't express something (OR across different fields,
`LIKE`, `StartsWith`, etc.), pass a raw string — kiwi passes it straight
through.

```ruby
client.invoices(
  tenant,
  where: 'Status=="AUTHORISED" || Status=="DRAFT"'
)
```

Consult Xero's [filter docs][xero-filters] for the full grammar.

[xero-filters]: https://developer.xero.com/documentation/api/accounting/requests-and-responses#retrieving-a-filtered-resource

## `order:` — sorting

Hash (typed) or string (raw passthrough).

```ruby
client.invoices(tenant, order: { date: :desc })
# => order=Date DESC

client.invoices(tenant, order: { date: :desc, invoice_number: :asc })
# => order=Date DESC,InvoiceNumber ASC

client.invoices(tenant, order: "Date DESC")
# passthrough
```

## `page:` — pagination

Maps directly to Xero's `page` query param (1-indexed). Xero's page size
is 100 items for paginated endpoints.

```ruby
client.invoices(tenant, page: 2).size          # => up to 100
client.invoices(tenant, page: 2).page_size     # => 100
client.invoices(tenant, page: 2).item_count    # total-on-this-page
```

### Walking every page — `each_<resource>`

For incremental syncs or whole-tenant scans, use the `each_*` helpers.
They take the same kwargs as the list method (minus `page:`), return a
lazy Enumerator when no block is given, and short-circuit when a short
page indicates no more data.

```ruby
client.each_invoice(tenant, where: { status: "AUTHORISED" }) do |invoice|
  Sync.upsert(invoice)
end

# Or use the Enumerator:
client.each_invoice(tenant, order: { date: :desc })
      .first(250)
      .map(&:invoice_id)
```

Available for every listable resource: `each_user`, `each_contact`,
`each_contact_group`, `each_invoice`, `each_credit_note`, `each_payment`,
`each_prepayment`, `each_overpayment`, `each_branding_theme`.

## `modified_since:` — incremental sync

Pass a `Time`; kiwi sends it as Xero's `If-Modified-Since` header in RFC
1123 format.

```ruby
page = client.invoices(tenant, modified_since: 1.day.ago)

page.each { |invoice| … }
```

If Xero returns `304 Not Modified`, kiwi returns an empty `Page` — no
exception, no special flag. An empty page after `modified_since:` is
indistinguishable from a filter that matched nothing (intentional — the
caller can treat them identically).

## Combining everything

Mix and match freely:

```ruby
client.invoices(
  tenant,
  where:          { status: "AUTHORISED", contact: { contact_id: "abc-123" } },
  order:          { date: :desc },
  page:           1,
  modified_since: last_sync_at
)
```

## What's queryable per resource?

Queryable fields are declared via `query: true` on each resource class's
`attribute` declarations. Identity fields (`invoice_id`, `contact_id`,
etc.) are queryable automatically.

You can inspect a resource's queryable fields at runtime:

```ruby
XeroKiwi::Accounting::Invoice.query_fields.keys
# => [:invoice_id, :invoice_number, :type, :contact, :date, :due_date,
#     :status, :updated_date_utc, :reference]
```

See the per-resource docs under `docs/accounting/` for the canonical list.
