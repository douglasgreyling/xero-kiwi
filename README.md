# Xero Kiwi

A Ruby wrapper for the [Xero](https://www.xero.com) Accounting API. XeroKiwi handles
the unglamorous parts of integrating with Xero — OAuth2, token refresh, rate
limiting, retries — so the rest of your code can focus on the actual business
problem.

## What's in the box

- **Full OAuth2 authorization-code flow** with PKCE support, CSRF state helpers,
  and OIDC ID token verification against Xero's JWKS.
- **Automatic token refresh** with proactive (before expiry) and reactive
  (on-401) handling, a callback hook for persisting rotated tokens, and a
  mutex to dedupe concurrent refreshes from multiple threads.
- **Rate-limit-aware retries** that honour Xero's `Retry-After` header on 429s
  and back off on transient 5xxs, built on `faraday-retry`.
- **A discoverable client surface** with explicit error classes for every
  failure mode (authentication, rate limit, code exchange, ID token verification,
  CSRF mismatch).
- **Connection management**: list and disconnect tenants, with token revocation
  for "disconnect Xero from my app" flows.
- **Accounting resources**: fetch contacts, organisations, users, branding
  themes, and nested objects like addresses, phones, external links, and payment
  terms — all wrapped in proper value objects.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "xero-kiwi"
```

Then run `bundle install`.

XeroKiwi requires Ruby 3.4.1 or newer.

## Quick start

```ruby
require "xero_kiwi"

# Once you've completed the OAuth flow and have an access token:
client = XeroKiwi::Client.new(access_token: "ya29...")
client.connections.each do |connection|
  puts "#{connection.tenant_name} (#{connection.tenant_type})"
end
```

For the full OAuth flow, refresh handling, and everything else, see the docs
below.

## Documentation

| Doc | What it covers |
|-----|----------------|
| [Getting started](docs/getting-started.md) | Installation, the mental model, your first end-to-end request |
| [Client](docs/client.md) | `XeroKiwi::Client` — every constructor option, request lifecycle, configuration |
| [Connections](docs/connections.md) | Listing tenants, the `XeroKiwi::Connection` resource, disconnecting tenants |
| [Contacts](docs/accounting/contact.md) | Listing and fetching contacts, the `XeroKiwi::Accounting::Contact` resource, nested ContactPerson |
| [Contact Groups](docs/accounting/contact-group.md) | Listing and fetching contact groups, the `XeroKiwi::Accounting::ContactGroup` resource |
| [Organisation](docs/accounting/organisation.md) | Fetching an organisation, the `XeroKiwi::Accounting::Organisation` resource, nested objects |
| [Users](docs/accounting/user.md) | Listing and fetching users, the `XeroKiwi::Accounting::User` resource, organisation roles |
| [Credit Notes](docs/accounting/credit-note.md) | Listing and fetching credit notes, the `XeroKiwi::Accounting::CreditNote` resource |
| [Invoices](docs/accounting/invoice.md) | Listing and fetching invoices/bills, the `XeroKiwi::Accounting::Invoice` resource |
| [Payments](docs/accounting/payment.md) | Listing and fetching payments, the `XeroKiwi::Accounting::Payment` resource |
| [Overpayments](docs/accounting/overpayment.md) | Listing and fetching overpayments, the `XeroKiwi::Accounting::Overpayment` resource |
| [Prepayments](docs/accounting/prepayment.md) | Listing and fetching prepayments, the `XeroKiwi::Accounting::Prepayment` resource, LineItem |
| [Branding Themes](docs/accounting/branding-theme.md) | Listing and fetching branding themes, the `XeroKiwi::Accounting::BrandingTheme` resource |
| [Tokens](docs/tokens.md) | The `XeroKiwi::Token` value object, automatic refresh, revocation, persistence callbacks |
| [OAuth](docs/oauth.md) | Authorization URL building, code exchange, PKCE, ID token verification, full Rails-style example |
| [Errors](docs/errors.md) | The error hierarchy, what to catch and when |
| [Retries and rate limits](docs/retries-and-rate-limits.md) | How XeroKiwi handles 429s and transient failures, customising the retry policy |

## Status

XeroKiwi is in early development. The API surface for the features documented above
is stable, but expect new resource methods to be added over time. Breaking
changes will be called out in the [changelog](CHANGELOG.md).

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/douglasgreyling/xero-kiwi.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
