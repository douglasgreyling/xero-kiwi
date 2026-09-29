# XeroKiwi::Client

`XeroKiwi::Client` is the entry point for talking to Xero's accounting API. You
construct one with credentials and call resource methods on it. The client
holds the OAuth token state, knows how to refresh it, and translates HTTP
errors into Xero Kiwi exceptions.

## Constructing a client

Two common shapes:

```ruby
# Simple — access token only, no refresh capability.
client = XeroKiwi::Client.new(access_token: "ya29...")

# Full — refresh-capable, with persistence callback.
client = XeroKiwi::Client.new(
  access_token:     credential.access_token,
  refresh_token:    credential.refresh_token,
  expires_at:       credential.expires_at,
  client_id:        ENV.fetch("XERO_CLIENT_ID"),
  client_secret:    ENV.fetch("XERO_CLIENT_SECRET"),
  on_token_refresh: ->(token) { credential.update!(token.to_h) }
)
```

The simple form is fine for one-off scripts and quick experiments. For
anything long-running, use the full form so the client can refresh tokens for
you. See [Tokens](tokens.md) for the full refresh story.

## Constructor options

| Option | Type | Required | Default | Purpose |
|--------|------|----------|---------|---------|
| `access_token:` | `String` | Yes | — | The OAuth2 bearer token used on every API call. |
| `refresh_token:` | `String` | No | `nil` | The refresh token. Required if you want the client to refresh expired access tokens. |
| `expires_at:` | `Time` | No | `nil` | When the access token expires. Used by the proactive refresh check. If `nil`, the client falls back to reactive refresh on 401. |
| `client_id:` | `String` | No | `nil` | Your Xero app's client ID. Required for refresh. |
| `client_secret:` | `String` | No | `nil` | Your Xero app's client secret. Required for refresh. |
| `on_token_refresh:` | `Proc` / lambda | No | `nil` | Called with the new `XeroKiwi::Token` whenever a refresh happens. Use this to persist the rotated token back to storage. |
| `adapter:` | `Symbol` / Faraday adapter | No | `Faraday.default_adapter` | The Faraday adapter to use. Override to swap in `:net_http_persistent`, `:typhoeus`, or a test adapter. |
| `user_agent:` | `String` | No | `"XeroKiwi/<version>"` | Sent as the `User-Agent` header on every request. |
| `retry_options:` | `Hash` | No | See [retries and rate limits](retries-and-rate-limits.md) | Overrides for the `faraday-retry` configuration. Merged into the defaults. |
| `throttle:` | Limiter | No | `XeroKiwi.default_throttle`, else none | Proactive per-tenant rate limiting. See [Throttling](throttling.md). |
| `page_size:` | `Integer` | No | `nil` (Xero's own default of 100) | Default `pageSize` for every list call. Per-call `page_size:` overrides it. See [Querying](querying.md). |
| `retain_raw:` | `Boolean` | No | `false` | Keep Xero's untouched response hash on each resource, readable via `#raw`. See below. |

### `retain_raw:` and `#raw`

By default a resource hydrates the fields kiwi models and discards the
original payload. Turn `retain_raw` on and each resource built directly
from a response keeps that payload:

```ruby
client  = XeroKiwi::Client.new(access_token: token, retain_raw: true)
contact = client.contact(tenant, contact_id)

contact.raw
# => {"ContactID" => "…", "ContactPersons" => [...], "SomeNewField" => "…"}
```

Use it to reach fields kiwi doesn't model yet.

Five things to know:

- **It's the item, not the envelope.** `contact.raw` has no `"Contacts"`
  key and `organisation.raw` has no `"Organisations"` key — kiwi unwraps
  the envelope before building a resource, so there's nothing left of it by
  the time `raw` is populated. If you need the envelope back, you're
  rebuilding it yourself.
- **Nested objects return `nil`, even with `retain_raw: true`.** Line
  items, addresses, contact persons and payment terms do not carry their
  own payload. Reach them through the enclosing resource's hash:

  ```ruby
  org.addresses.map(&:raw)   # => [nil]   ← not what you want
  org.raw["Addresses"]       # => [{"AddressType" => "POBOX", …}]
  ```

  This is deliberate — see [why nested objects don't carry
  raw](#why-nested-objects-dont-carry-raw) — but it fails quietly, so it's
  worth knowing before you map over a collection and store the result.
- **It's the JSON representation.** Kiwi sends
  `Accept: application/json`. Xero also serves XML, which nests
  differently — XML has no arrays, so a single child parses to a Hash and
  several to an Array, where JSON is always an Array. `raw` cannot
  reproduce an XML-derived shape. See [migrating from an XML
  client](#migrating-from-an-xml-based-client) below.
- **`#raw` is not `#to_h`.** `to_h` is a snake_case projection rebuilt from
  the modelled attributes — different keys, different nesting. If you store
  `to_h` where you meant to store the payload, readers fail by returning
  nil rather than raising.
- **It costs memory.** Every resource holds its source hash alongside the
  hydrated attributes, which roughly doubles the footprint of a large page.
  That's why it's off by default.

### What `raw` guarantees

Depend on these; they won't change without a major version.

- It is the parsed JSON for that resource, with **only the top-level keys
  stringified**. Everything nested is exactly what `JSON.parse` produced.
- **Kiwi does not normalise it.** No key renaming, no defaulting, no
  filling in of absent keys. If Xero omits `Addresses`, `raw` has no
  `"Addresses"` key — it does not become `[]`. If Xero sends `[]`, you get
  `[]`. `raw.fetch("Addresses", [])` and `raw["Addresses"] || []` are both
  safe and mean the same thing here.
- Keys the gem doesn't model are preserved. That's the point of it.
- The top-level hash is **frozen; nested structures are not**. `raw` itself
  can't be mutated, but `raw["Addresses"]` is an ordinary mutable Array.
  Dup before mutating if that matters to you.

The one thing deliberately *not* guaranteed is the presence of `raw` on
nested objects, per the bullet above.

**This is where `raw` and the typed attributes differ on purpose.** Xero
sends `""` for a text field with no value; the modelled attribute reads it
as `nil`, while `raw` keeps the `""` exactly as it arrived:

```ruby
theme.logo_url        # => nil
theme.raw["LogoUrl"]  # => ""
```

That empty string is otherwise easy to carry into a database column, where
it quietly changes what queries match — a `where.not(logo_url: nil)` starts
returning rows with no logo. `type: :date` has always made this call;
strings doing otherwise was an inconsistency. Only exactly `""` is
affected: `" "` is left alone, because trimming it would be editorialising
on a value rather than recognising an absent one.

### Why nested objects don't carry raw

Two reasons, both worth knowing if you're tempted to ask for it.

It would cost real memory on the workload `retain_raw` exists for. A page
of 1,000 invoices with five line items each retains about 3.4 MB with
top-level raw; giving every nested object its own hash adds about 1.6 MB
on top, roughly half again, and that's on a flag that has already doubled
your footprint.

More importantly it couldn't be done consistently. Several attributes —
`payment_terms` on Contact and Organisation, `invoice_addresses` on
Invoice — hydrate through custom lambdas that construct their objects
directly, so they'd stay `nil` while their siblings worked. "Nested
objects never carry raw" is a rule you can hold in your head. "Nested
objects carry raw except these four" is not.

### Migrating from an XML-based client

If you're replacing a Xero client that sent `Accept: text/xml` — HTTParty
and similar default to it — any payloads you already have stored are
XML-shaped, and `raw` will not match them. The differences are structural,
not cosmetic:

| | XML (`text/xml`) | JSON (`application/json`) |
|---|---|---|
| Organisation body | `{"Organisations" => {"Organisation" => {…}}}` | `{"Organisations" => [{…}]}` |
| One address | `{"Address" => {…}}` | `[{…}]` |
| Several addresses | `{"Address" => [{…}, {…}]}` | `[{…}, {…}]` |

The single-child collapse is the one that catches people: under XML a
contact with one person parses to a Hash and a contact with two parses to
an Array, from the same endpoint. Code written against that has a
normalising step somewhere, whether or not its author knew why.

**Key names can differ too, not only nesting.** It is tempting to assume the
two representations agree on field names and diverge only in structure. They
don't. An allocation's value is `Amount` in JSON and `AppliedAmount` in XML —
same field, same record, different name — and nothing in Xero's
documentation says so. Two separate silent-nil bugs in this gem came from
assuming otherwise, each one an importer writing `0.0` into every allocated
amount with nothing raising.

So when you check a field against stored XML-era payloads, you are checking
its name as well as its shape. If a modelled attribute comes back nil
against real JSON, suspect the key before suspecting the data.

No client setting reproduces these shapes — they're artefacts of an XML
parse kiwi doesn't do. But the remedy isn't the same everywhere, and it's
worth sorting your readers into two piles before planning the work.

**Readers that dig the XML-only structure have to change.** Something like
`dig("Organisations", "Organisation", "Addresses", "Address")` returns nil
against anything kiwi produces, whether you store `raw` or `to_h`.
Promote the fields those readers need to real columns and use `raw` for
the backfill — it's the true payload, so it carries everything required to
populate them.

**Readers that already normalise usually survive untouched.** A reader
doing `[value].flatten.compact` handles the Hash case, the Array case and
nil identically, so a JSON array flows straight through. If the keys it
reads are the same in both representations, only the *writer* changes:
stop unwrapping, store the array. Existing rows stay readable, and you
skip a migration entirely.

**Types change too, and booleans are where it bites.** XML has no types, so
everything arrives as a string: `"false"`, not `false`. JSON gives you the
real thing. If your reader passes the value through a caster —
ActiveModel's boolean cast, say — both land on the same result and you'll
never notice. If it relies on plain Ruby truthiness, the two are opposites:

```ruby
"false" ? :yes : :no   # => :yes   ← every non-empty string is truthy
false   ? :yes : :no   # => :no
```

A reader doing `select(&:included)` over an XML-derived `"false"` has been
selecting the records it was meant to exclude, for as long as that code has
existed. Moving to kiwi *fixes* it — which means the behaviour changes at
cutover, in a way your users may see. Find those readers before you switch,
not after: grep for boolean-ish fields consumed without a cast.

This is the third axis on which the two representations differ, after
nesting and key names. Treat "it's the same field, so it's the same value"
as the assumption to check rather than the one to rely on.

**Money is a `BigDecimal`, not a String and not a Float.** An XML client
hands you `"19812.97"`; Xero's JSON sends the number `19812.97`, which Ruby
parses as a Float. Kiwi converts every money field to `BigDecimal` on the
way in, because Floats cannot represent most decimal fractions and so
arithmetic between two of them drifts:

```ruby
17228.67 + 2584.3            # => 19812.969999999998   ← Float
invoice.sub_total + invoice.total_tax == invoice.total # => true
```

That identity failed on 3 of the 55 invoices in this gem's recorded
response as Floats, and on none of them as BigDecimals. Each individual
value was correct in both — it is only arithmetic between fields that goes
wrong, which is what makes it quiet.

For migration this mostly helps. Comparison is not a concern —
`BigDecimal("19812.97")` equals the Float `19812.97`, equals
`BigDecimal("19812.97")`, and `BigDecimal("100")` equals `100` — and a
`decimal`/`numeric` column takes it unchanged. Two things do change:

- **`to_s` gives `"0.1981297e5"`**, not `"19812.97"`. Use `to_s("F")` for a
  plain decimal string.
- **`to_json` gives the string `"0.1981297e5"`**, where a Float gave the
  number `19812.97`. Writing a **typed** money attribute into a `jsonb`
  column or an API response changes the stored shape — from a JSON number
  to a JSON string in scientific notation. Call `to_s("F")` or `to_f` on
  the way in, depending on which you want.

  **`raw` is not affected.** It holds Xero's parsed payload untouched, so a
  money value in there is still a Float and still serialises as a JSON
  number. A consumer whose `jsonb` columns are fed from `raw` sees no
  change at all — that separation is the whole point of `raw`.

`is_a?(Float)` is also now false, though `is_a?(Numeric)` still holds.

**Check for `.to_f` on money you persist.** Converting back to Float
immediately undoes this change, and does so silently: a `decimal(19,4)`
column holds more precision than a Float can carry, so the round trip loses
digits rather than raising.

```ruby
BigDecimal("1234567890123.4567").round(4)             # => 1234567890123.4567
BigDecimal("1234567890123.4567").to_f.to_d.round(4)   # => 1234567890123.456
BigDecimal("999999999999999.9999").to_f.to_d.round(4) # => 1000000000000000.0
```

Out of reach for currencies like GBP or ZAR at ordinary invoice sizes, not
for IDR or VND. A `.to_f` left over from an XML-era client — where the value
arrived as a String and had to be converted — is the likely place to find
one.

One piece of luck worth knowing about: the two piles tend to fail
differently. A `dig` that misses returns nil and writes a blank record
quietly. Code that assumed a Hash, such as `Array#to_h` on what is now a
list, raises `TypeError` on the first record with data in it. The noisy
failures are the ones you can trust to find themselves — budget your
review time for the silent ones.

## What the client gives you

| Method | Returns | Purpose |
|--------|---------|---------|
| `client.connections` | `Array<XeroKiwi::Connection>` | Fetch the tenants this token is authorised against. See [Connections](connections.md). |
| `client.contacts(tenant_id_or_connection)` | `Array<XeroKiwi::Accounting::Contact>` | Fetch the contacts for a tenant. See [Contacts](accounting/contact.md). |
| `client.contact(tenant_id_or_connection, contact_id)` | `XeroKiwi::Accounting::Contact` | Fetch a single contact by ID. See [Contacts](accounting/contact.md). |
| `client.contact_groups(tenant_id_or_connection)` | `Array<XeroKiwi::Accounting::ContactGroup>` | Fetch the contact groups for a tenant. See [Contact Groups](accounting/contact-group.md). |
| `client.contact_group(tenant_id_or_connection, contact_group_id)` | `XeroKiwi::Accounting::ContactGroup` | Fetch a single contact group by ID. See [Contact Groups](accounting/contact-group.md). |
| `client.organisation(tenant_id_or_connection)` | `XeroKiwi::Accounting::Organisation` | Fetch the organisation for a tenant. See [Organisation](accounting/organisation.md). |
| `client.users(tenant_id_or_connection)` | `Array<XeroKiwi::Accounting::User>` | Fetch the users for a tenant. See [Users](accounting/user.md). |
| `client.user(tenant_id_or_connection, user_id)` | `XeroKiwi::Accounting::User` | Fetch a single user by ID. See [Users](accounting/user.md). |
| `client.credit_notes(tenant_id_or_connection)` | `Array<XeroKiwi::Accounting::CreditNote>` | Fetch the credit notes for a tenant. See [Credit Notes](accounting/credit-note.md). |
| `client.credit_note(tenant_id_or_connection, credit_note_id)` | `XeroKiwi::Accounting::CreditNote` | Fetch a single credit note by ID. See [Credit Notes](accounting/credit-note.md). |
| `client.invoices(tenant_id_or_connection)` | `Array<XeroKiwi::Accounting::Invoice>` | Fetch the invoices for a tenant. See [Invoices](accounting/invoice.md). |
| `client.invoice(tenant_id_or_connection, invoice_id)` | `XeroKiwi::Accounting::Invoice` | Fetch a single invoice by ID. See [Invoices](accounting/invoice.md). |
| `client.online_invoice_url(tenant_id_or_connection, invoice_id)` | `String` | Fetch the online invoice URL for a sales invoice. See [Invoices](accounting/invoice.md). |
| `client.payments(tenant_id_or_connection)` | `Array<XeroKiwi::Accounting::Payment>` | Fetch the payments for a tenant. See [Payments](accounting/payment.md). |
| `client.payment(tenant_id_or_connection, payment_id)` | `XeroKiwi::Accounting::Payment` | Fetch a single payment by ID. See [Payments](accounting/payment.md). |
| `client.overpayments(tenant_id_or_connection)` | `Array<XeroKiwi::Accounting::Overpayment>` | Fetch the overpayments for a tenant. See [Overpayments](accounting/overpayment.md). |
| `client.overpayment(tenant_id_or_connection, overpayment_id)` | `XeroKiwi::Accounting::Overpayment` | Fetch a single overpayment by ID. See [Overpayments](accounting/overpayment.md). |
| `client.prepayments(tenant_id_or_connection)` | `Array<XeroKiwi::Accounting::Prepayment>` | Fetch the prepayments for a tenant. See [Prepayments](accounting/prepayment.md). |
| `client.prepayment(tenant_id_or_connection, prepayment_id)` | `XeroKiwi::Accounting::Prepayment` | Fetch a single prepayment by ID. See [Prepayments](accounting/prepayment.md). |
| `client.branding_themes(tenant_id_or_connection)` | `Array<XeroKiwi::Accounting::BrandingTheme>` | Fetch the branding themes for a tenant. See [Branding Themes](accounting/branding-theme.md). |
| `client.branding_theme(tenant_id_or_connection, branding_theme_id)` | `XeroKiwi::Accounting::BrandingTheme` | Fetch a single branding theme by ID. See [Branding Themes](accounting/branding-theme.md). |
| `client.delete_connection(id_or_connection)` | `true` | Disconnect a tenant. See [Connections](connections.md). |
| `client.token` | `XeroKiwi::Token` | The current in-memory token. Inspect expiry, refreshability, etc. |
| `client.token.expired?` | `Boolean` | True if `expires_at` is in the past. |
| `client.token.expiring_soon?(within: 60)` | `Boolean` | True if `expires_at` falls inside the window. |
| `client.token.refreshable?` | `Boolean` | True if the token has a refresh token attached. |
| `client.can_refresh?` | `Boolean` | True if the client was constructed with both refresh credentials AND the current token has a `refresh_token`. |
| `client.refresh_token!` | `XeroKiwi::Token` | Force a refresh now. Returns the new token. Raises `XeroKiwi::TokenRefreshError` if there's no refresh capability. |
| `client.revoke_token!` | `true` | Revoke the current refresh token at Xero. Use for logout / "disconnect Xero" flows. See [Tokens](tokens.md). |

## The request lifecycle

Every API call goes through `with_authenticated_request`, which wraps the
actual HTTP call with two layers of token-freshness handling:

1. **Proactive refresh.** Before the request fires, if the token is expiring
   within the default window (60 seconds) AND the client has refresh
   capability, the client refreshes the token first. This covers the common
   case of "the token I loaded from the database is about to expire."
2. **The actual HTTP call** — including all the retry behaviour described
   in [retries and rate limits](retries-and-rate-limits.md).
3. **Reactive refresh on 401.** If the request returns a 401 anyway (token
   was revoked early, our clock is wrong, etc.), the client refreshes once
   and retries the request. A `retried` flag prevents an infinite loop —
   the second 401 raises `XeroKiwi::AuthenticationError`.

If you constructed the client without refresh credentials, both layers are
skipped: a 401 raises immediately and you handle it in your own code.

## Custom adapters

Xero Kiwi uses Faraday under the hood, so you can swap the HTTP adapter for
testing or for connection pooling:

```ruby
client = XeroKiwi::Client.new(
  access_token: "...",
  adapter:      :net_http_persistent
)
```

For tests:

```ruby
require "faraday"

client = XeroKiwi::Client.new(
  access_token: "...",
  adapter:      [:test, Faraday::Adapter::Test::Stubs.new] # or use webmock
)
```

The adapter is also passed through to the internal `TokenRefresher`, so a
test adapter swallows refresh requests too.

## Customising the retry policy

`retry_options:` is merged into Xero Kiwi's defaults, so you only need to specify
overrides:

```ruby
client = XeroKiwi::Client.new(
  access_token: "...",
  retry_options: {
    max:      8,        # try up to 8 retries (default: 4)
    interval: 1.0       # initial wait of 1 second (default: 0.5)
  }
)
```

See [retries and rate limits](retries-and-rate-limits.md) for the full
configuration reference and which keys you can override.

## Thread safety

A single client can safely be shared across threads. The internals are
thread-safe in two specific ways:

- **Token refresh** is protected by a `Mutex` with a double-check pattern. If
  two threads both notice the token is expiring at the same time, only one
  will actually call Xero's refresh endpoint; the other waits, then sees the
  fresh token and proceeds.
- **Faraday connections** are reused across threads (Faraday's adapters are
  designed for this).

There's one caveat: **manual `refresh_token!` calls don't double-check.** If
you call `client.refresh_token!` from two threads simultaneously, both will
hit Xero, and the second will fail because the refresh token rotated. The
automatic path (`ensure_fresh_token!` inside `with_authenticated_request`)
deduplicates correctly.

If you're sharing a client across multiple processes (e.g. a Sidekiq pool
spread across machines), the in-process mutex doesn't help you. See
[Tokens](tokens.md#multi-process-refresh) for the multi-process gotcha and
how to handle it.

## What the client deliberately does NOT do

- **Persist anything.** The client never writes to your database, session,
  or filesystem. The `on_token_refresh` callback is your hook for that.
- **Manage OAuth state.** The client doesn't know about CSRF state or PKCE
  verifiers. Use [`XeroKiwi::OAuth`](oauth.md) for the auth-code flow.
- **Validate scopes.** If your token doesn't have the right scope for an
  endpoint, you'll get a 403 from Xero. The client surfaces it as a
  `XeroKiwi::ClientError`; it's the caller's job to know what scopes they
  asked for.
