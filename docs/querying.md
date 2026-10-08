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

## `page_size:` — how many per page

Maps to Xero's `pageSize` query param. Xero's own default is 100 and its
maximum is 1,000 on most paged endpoints.

Set it once on the client and every call inherits it; override per call
where you need something different.

```ruby
client = XeroKiwi::Client.new(access_token: token, page_size: 1_000)

client.invoices(tenant)                  # pageSize=1000
client.invoices(tenant, page_size: 100)  # this call only
```

Leave it unset and kiwi omits the parameter entirely, so Xero applies its
own default.

This is worth setting for any full-tenant sync. At 100 per page a
50,000-invoice tenant costs ~500 API calls; at 1,000 it costs ~50, against
a daily limit of 5,000.

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
`each_prepayment`, `each_overpayment`, `each_branding_theme`,
`each_tracking_category`.

### Walking pages instead of items — `each_<resource>_page`

Same walk, but each yield is a whole `Page` rather than one item. Use it
when you need the page number — which is what makes a sync resumable.

```ruby
client.each_invoice_page(tenant, page_size: 1_000) do |page|
  Invoice.upsert_all(page.map(&:to_h))
  cursor.update!(invoices: page.page)   # same transaction as the upsert
end
```

Recording the page number in the same transaction that stores the rows
matters: a marker written when the response lands, before the rows are
saved, can survive a crash that the rows don't — and the next run then
skips a page it never actually imported.

### Resuming — `start_page:`

Both `each_*` and `each_*_page` accept `start_page:` (default 1), so a
resumed run picks up where the last one stopped.

```ruby
client.each_invoice_page(tenant, start_page: cursor.invoices + 1) do |page|
  …
end
```

### How the walk knows when to stop

It stops on an empty page, or on a page shorter than a full one. "Full" is
measured against Xero's stated page size when the response carries a
`pagination` envelope, and otherwise against the largest page seen so far
in that walk.

It is deliberately **not** measured against the `page_size:` you asked
for. Xero clamps a request above an endpoint's maximum, so a walk that
asked for 2,000 where the cap is 1,000 would see its very first page as
short and stop after one page — silently truncating the sync. The cost of
measuring instead of assuming is one extra request when the whole result
fits in a single page and no envelope came back.

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

## `include_archived:` — archived contacts and tracking categories

Contacts and tracking categories only. Maps to Xero's `includeArchived`
query param, which returns archived records **alongside** active ones in
the same pass.

```ruby
client.contacts(tenant, include_archived: true)
client.each_contact(tenant, include_archived: true) { |contact| … }

client.tracking_categories(tenant, include_archived: true)
client.each_tracking_category(tenant, include_archived: true) { |category| … }
```

This is not the same as filtering on `contact_status`. A
`where: { contact_status: "ARCHIVED" }` returns *only* archived contacts;
`include_archived: true` returns both kinds together, which is what you
want when mirroring a tenant's full contact list.

It matters beyond contacts themselves: Xero keeps serving archived
contacts as members of contact groups, so without this you can't tell
which group members are archived locally.

For tracking categories it reaches the options too. Without it, Xero leaves
out archived categories *and* the archived options under active ones. Line
items keep pointing at an archived option, so a sync that mirrors the list
without this flag deletes options its invoices still refer to.

## Combining everything

Mix and match freely:

```ruby
client.invoices(
  tenant,
  where:          { status: "AUTHORISED", contact: { contact_id: "abc-123" } },
  order:          { date: :desc },
  page:           1,
  page_size:      1_000,
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
