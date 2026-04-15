# Getting started

This guide walks you from a fresh checkout to your first successful Xero API
call. If you already know what OAuth2 is and just want the API reference, jump
straight to [Client](client.md) or [OAuth](oauth.md).

## Prerequisites

Before you can talk to Xero from Ruby, you need:

1. **A Xero developer account.** Sign up at
   <https://developer.xero.com>.
2. **A Xero app**, registered in the developer portal. The app gives you a
   `client_id` and `client_secret` and lets you configure a redirect URL.
3. **Ruby 3.4.1 or newer.**

## Installing the gem

Add XeroKiwi to your `Gemfile`:

```ruby
gem "xero-kiwi"
```

Then:

```sh
bundle install
```

## The mental model

XeroKiwi is built around a small set of objects, each with one job:

| Object | What it does |
|--------|--------------|
| [`XeroKiwi::OAuth`](oauth.md) | Drives the OAuth2 authorization-code flow. Builds authorise URLs, exchanges codes for tokens, verifies ID tokens, revokes tokens. |
| [`XeroKiwi::Token`](tokens.md) | An immutable value object holding an access/refresh pair plus expiry metadata. Knows when it's expired or expiring. |
| [`XeroKiwi::Client`](client.md) | The API gateway. You give it a token (or full credentials) and call methods like `client.connections`. Handles retries, refresh, error mapping. |
| [`XeroKiwi::Connection`](connections.md) | A Xero "connection" — one tenant (organisation or practice) that an access token is authorised against. |
| [`XeroKiwi::Accounting::Organisation`](accounting/organisation.md) | A Xero organisation — the accounting entity (company, trust, etc.) behind a tenant. |

The flow is always: **OAuth → Token → Client → resources.** OAuth gets you a
Token; you hand the Token to a Client; the Client lets you call resource
methods.

## Your first request — the short version

If you already have an access token (e.g. from a previous OAuth dance, or from
the Xero developer portal's "Try it" tooling), making a request is one line:

```ruby
require "xero_kiwi"

client = XeroKiwi::Client.new(access_token: "ya29...")
client.connections # => [#<XeroKiwi::Connection ...>, ...]
```

This is enough to get started, but the access token will expire after 30
minutes and you have no way to refresh it. For anything beyond a quick script,
read on.

## Your first request — the full version

A production-grade integration looks more like this:

```ruby
require "xero_kiwi"

# 1. Set up the OAuth helper. You only need redirect_uri for the auth-code
#    flow itself; for refresh-only / revoke-only callers it's optional.
oauth = XeroKiwi::OAuth.new(
  client_id:     ENV.fetch("XERO_CLIENT_ID"),
  client_secret: ENV.fetch("XERO_CLIENT_SECRET"),
  redirect_uri:  "https://app.example.com/xero/callback"
)

# 2. Send the user to Xero. Stash the state + PKCE verifier in your session
#    so you can verify them when the user comes back.
state = XeroKiwi::OAuth.generate_state
pkce  = XeroKiwi::OAuth.generate_pkce
session[:xero_state]    = state
session[:xero_verifier] = pkce.verifier

redirect_to oauth.authorization_url(
  scopes: %w[openid profile email accounting.transactions offline_access],
  state:  state,
  pkce:   pkce
)

# 3. In your callback handler, verify state, exchange the code, persist the
#    tokens, and you're ready to call the API.
XeroKiwi::OAuth.verify_state!(
  received: params[:state],
  expected: session.delete(:xero_state)
)

token = oauth.exchange_code(
  code:          params[:code],
  code_verifier: session.delete(:xero_verifier)
)

XeroCredential.create!(
  access_token:  token.access_token,
  refresh_token: token.refresh_token,
  expires_at:    token.expires_at
)

# 4. Now build a refresh-capable client and use it. The client will refresh
#    automatically when the token expires; the on_token_refresh callback
#    persists the rotated token back to your storage.
credential = XeroCredential.last

client = XeroKiwi::Client.new(
  access_token:     credential.access_token,
  refresh_token:    credential.refresh_token,
  expires_at:       credential.expires_at,
  client_id:        ENV.fetch("XERO_CLIENT_ID"),
  client_secret:    ENV.fetch("XERO_CLIENT_SECRET"),
  on_token_refresh: ->(token) { credential.update!(token.to_h) }
)

client.connections.each do |connection|
  puts "#{connection.tenant_name} (#{connection.tenant_id})"
end
```

That's the whole loop: authorise, exchange, persist, call the API.

## Where to go next

- [OAuth](oauth.md) — the full reference for the auth-code flow, PKCE, ID token
  verification, and revocation.
- [Client](client.md) — every constructor option for `XeroKiwi::Client`, the request
  lifecycle, custom adapters and retry policy.
- [Tokens](tokens.md) — how refresh works, the persistence callback, manual vs
  automatic refresh, multi-process gotchas.
- [Errors](errors.md) — the full error hierarchy and what to rescue when.
