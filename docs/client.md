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
- **It's per resource, not per nested object.** Line items, addresses and
  contact persons have no `#raw` of their own. They don't need one: the
  resource's hash already holds every nested payload, so
  `contact.raw["ContactPersons"]` gets there.
- **It costs memory.** Every resource holds its source hash alongside the
  hydrated attributes, which roughly doubles the footprint of a large page.
  That's why it's off by default.

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

Type coercion is usually fine in that second pile too. XML gives you
strings — `"false"` rather than `false` — and if the reader hands that to
something like ActiveModel's boolean cast, both the old string and the new
real boolean land on the same value.

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
