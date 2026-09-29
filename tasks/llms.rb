# frozen_string_literal: true

# Builds the two LLM-facing documentation bundles from one manifest:
#
#   llms.txt       - curated index. Title, summary, and a linked list of
#                    every doc with a one-line description.
#   llms-full.txt  - every doc concatenated in reading order.
#
# Both derive from DOCS below, so adding a doc means adding one entry and
# nothing else. `llms:check` fails if either file is stale OR if a doc
# exists on disk that the manifest doesn't mention — llms.txt drifted for
# six months and four releases because nothing enforced that second half.
module Llms
  module_function

  REPO     = "https://github.com/douglasgreyling/xero-kiwi"
  RAW_BASE = "https://raw.githubusercontent.com/douglasgreyling/xero-kiwi/main"

  INDEX_PATH = "llms.txt"
  FULL_PATH  = "llms-full.txt"

  # Docs that live outside docs/ and so aren't covered by the
  # "every doc is in the manifest" check.
  ROOT_DOCS = %w[README.md CHANGELOG.md].freeze

  # Reading order. `optional: true` moves an entry into llms.txt's
  # "Optional" section — secondary material a reader on a tight context
  # budget can skip. It has no effect on llms-full.txt.
  DOCS = [
    { path: "README.md", title: "README",
      summary: "high-level overview, installation, the documentation table of contents, and the development and release process",
      optional: true },
    { path: "docs/getting-started.md", title: "Getting started",
      summary: "installation, the mental model, and a full end-to-end example from authorise to first API call" },
    { path: "docs/client.md", title: "Client",
      summary: "every constructor option for `XeroKiwi::Client`, the request lifecycle (proactive + reactive token refresh), " \
               "`page_size` and `retain_raw`, the `#raw` contract, migrating from an XML-based client, custom adapters, thread safety" },
    { path: "docs/oauth.md", title: "OAuth",
      summary: "the full auth-code flow, PKCE, state generation and verification, ID token verification with JWKS caching, " \
               "token revocation, full Rails-style example" },
    { path: "docs/tokens.md", title: "Tokens",
      summary: "the `XeroKiwi::Token` value object, expiry helpers, automatic and manual refresh, the `on_token_refresh` " \
               "callback, the refresh-token rotation gotcha, multi-process refresh patterns" },
    { path: "docs/connections.md", title: "Connections",
      summary: "listing tenants, the `XeroKiwi::Connection` resource (id vs tenant_id), disconnecting tenants" },
    { path: "docs/querying.md", title: "Querying",
      summary: "`where` / `order` / `page` / `page_size` / `include_archived` / `modified_since` on list endpoints, the " \
               "`XeroKiwi::Page` return type, `each_*` and `each_*_page` lazy walks, `start_page:` resumability, how a walk decides to stop" },
    { path: "docs/accounting/contact.md", title: "Contacts",
      summary: "listing and fetching contacts, the `XeroKiwi::Accounting::Contact` resource, nested ContactPerson, predicates" },
    { path: "docs/accounting/contact-group.md", title: "Contact Groups",
      summary: "listing and fetching contact groups, the `XeroKiwi::Accounting::ContactGroup` resource" },
    { path: "docs/accounting/organisation.md", title: "Organisation",
      summary: "fetching an organisation, the `XeroKiwi::Accounting::Organisation` resource, date parsing nuances " \
               "(ISO 8601 vs .NET JSON format)" },
    { path: "docs/accounting/user.md", title: "Users",
      summary: "listing and fetching users, the `XeroKiwi::Accounting::User` resource, organisation roles" },
    { path: "docs/accounting/credit-note.md", title: "Credit Notes",
      summary: "listing and fetching credit notes, the `XeroKiwi::Accounting::CreditNote` resource, allocations" },
    { path: "docs/accounting/invoice.md", title: "Invoices",
      summary: "listing and fetching invoices/bills, the `XeroKiwi::Accounting::Invoice` resource, line items, payments, " \
               "online invoice URLs" },
    { path: "docs/accounting/payment.md", title: "Payments",
      summary: "listing and fetching payments, the `XeroKiwi::Accounting::Payment` resource, reconciliation" },
    { path: "docs/accounting/overpayment.md", title: "Overpayments",
      summary: "listing and fetching overpayments, the `XeroKiwi::Accounting::Overpayment` resource, allocations" },
    { path: "docs/accounting/prepayment.md", title: "Prepayments",
      summary: "listing and fetching prepayments, the `XeroKiwi::Accounting::Prepayment` resource, LineItem value object" },
    { path: "docs/accounting/branding-theme.md", title: "Branding Themes",
      summary: "listing and fetching branding themes, the `XeroKiwi::Accounting::BrandingTheme` resource" },
    { path: "docs/accounting/tracking-category.md", title: "Tracking Categories",
      summary: "listing and fetching tracking categories, and the difference between `TrackingCategory` (the endpoint " \
               "resource, with options), `TrackingOption`, and `Tracking` (the assignment nested on line items)" },
    { path: "docs/accounting/address.md", title: "Address",
      summary: "the `XeroKiwi::Accounting::Address` value object (shared by Organisation, Contact)" },
    { path: "docs/accounting/phone.md", title: "Phone",
      summary: "the `XeroKiwi::Accounting::Phone` value object (shared by Organisation, Contact)" },
    { path: "docs/accounting/external-link.md", title: "ExternalLink",
      summary: "the `XeroKiwi::Accounting::ExternalLink` value object" },
    { path: "docs/accounting/payment-terms.md", title: "PaymentTerms",
      summary: "the `XeroKiwi::Accounting::PaymentTerms` and `XeroKiwi::Accounting::PaymentTerm` value objects" },
    { path: "docs/errors.md", title: "Errors",
      summary: "the full error hierarchy (`XeroKiwi::Error`, `APIError`, `AuthenticationError`, `ClientError`, `ServerError`, " \
               "`TokenRefreshError`, `RateLimitError`, `OAuth::StateMismatchError`, `OAuth::CodeExchangeError`, " \
               "`OAuth::IDTokenError`, `Throttle::Timeout`, `Throttle::DailyLimitExhausted`), what to catch when" },
    { path: "docs/retries-and-rate-limits.md", title: "Retries and rate limits",
      summary: "how XeroKiwi handles 429s and transient 5xxs, `client.rate_limit(tenant_id)` for remaining quota (process-local), " \
               "recording a durable per-tenant back-off signal from the `tenant_id` and `retry_after` carried by RateLimitError " \
               "and the throttle errors, tuning the retry policy, the Faraday middleware ordering, why 500 is deliberately not retried",
      optional: true },
    { path: "docs/throttling.md", title: "Throttling",
      summary: "the Redis-backed per-tenant token bucket for coordinating rate limits across processes, `default_throttle`, what " \
               "per_minute/per_day actually guarantee (a fresh bucket bursts to roughly double in the first window), " \
               "`#remaining`, fail-open behaviour, writing a custom limiter",
      optional: true },
    { path: "CHANGELOG.md", title: "CHANGELOG",
      summary: "version history",
      optional: true }
  ].freeze

  INDEX_INTRO = <<~MARKDOWN
    # XeroKiwi

    > A Ruby wrapper for the Xero Accounting API. Handles OAuth2, token refresh,
    > rate limiting, retries, and error mapping so the rest of your code can
    > focus on the business problem.

    The flow is always: **OAuth → Token → Client → resources.** OAuth gets you a
    Token, you hand the Token to a Client, the Client lets you call resource
    methods.

    Core objects:

    - `XeroKiwi::OAuth` drives the OAuth2 authorization-code flow (build authorise URLs, exchange codes for tokens, verify ID tokens, revoke tokens).
    - `XeroKiwi::Token` is the immutable value object holding the access/refresh pair plus expiry metadata, with helpers like `expired?`, `expiring_soon?`, and `refreshable?`.
    - `XeroKiwi::Client` is the API gateway. Give it a token (or full credentials) and call resource methods like `client.connections`. Handles automatic token refresh (proactive + reactive), rate-limit retries, and error mapping.
    - `XeroKiwi::Connection` is a Xero "connection" — one tenant (organisation or practice) that an access token is authorised against.
    - `XeroKiwi::Page` is what every list method returns — Enumerable, plus `page`, `page_size`, `item_count` and `total_count`.
    - `XeroKiwi::RateLimit` reports remaining quota for a tenant, taking the stricter of what Xero last reported and what the configured throttle bucket holds.
    - `XeroKiwi::Throttle::RedisTokenBucket` is the optional proactive limiter — a per-tenant token bucket in Redis, shared across processes.

    Accounting resources:

    - `XeroKiwi::Accounting::Contact` is a Xero contact — a customer, supplier, or both, with nested `Address`, `Phone`, `ContactPerson`, and `PaymentTerms` value objects.
    - `XeroKiwi::Accounting::ContactGroup` is a Xero contact group — a named collection of contacts for organising customers or suppliers.
    - `XeroKiwi::Accounting::Organisation` is a Xero organisation — the accounting entity behind a tenant, with nested `Address`, `Phone`, `ExternalLink`, and `PaymentTerms` value objects.
    - `XeroKiwi::Accounting::User` is a Xero user — someone who has access to a Xero organisation, with their role and subscriber status.
    - `XeroKiwi::Accounting::Invoice` is a Xero invoice — a sales invoice (ACCREC) or purchase bill (ACCPAY), with line items, payments, and allocation details.
    - `XeroKiwi::Accounting::CreditNote` is a Xero credit note — a document that reduces the amount owed on an invoice, with allocations and line items.
    - `XeroKiwi::Accounting::Payment` is a Xero payment — money received or paid against invoices, credit notes, prepayments, or overpayments.
    - `XeroKiwi::Accounting::Overpayment` is a Xero overpayment — an excess payment received or made, with allocations and line items.
    - `XeroKiwi::Accounting::Prepayment` is a Xero prepayment — a payment received or made in advance, with nested `LineItem` objects.
    - `XeroKiwi::Accounting::Allocation` links a credit note, prepayment, or overpayment to an invoice, with an `invoice` reference.
    - `XeroKiwi::Accounting::BrandingTheme` is a Xero branding theme — controls the look and feel of invoices and other documents.
    - `XeroKiwi::Accounting::TrackingCategory` is a tracking category definition from `/TrackingCategories`, with its `TrackingOption`s. Distinct from `XeroKiwi::Accounting::Tracking`, which is the flattened assignment nested on line items and contacts.

    Every list endpoint accepts `where`, `order`, `page`, `page_size` and `modified_since`, and has lazy `each_<resource>` and `each_<resource>_page` helpers for whole-tenant scans.

    XeroKiwi requires Ruby 3.4.1 or newer. Install with `gem "xero-kiwi"`.
  MARKDOWN

  def build_index
    out = +""
    out << INDEX_INTRO
    out << "\n## Docs\n\n"
    DOCS.reject { |d| d[:optional] }.each { |d| out << link_line(d) }
    out << "\n## Optional\n\n"
    DOCS.select { |d| d[:optional] }.each { |d| out << link_line(d) }
    out
  end

  def link_line(doc)
    "- [#{doc[:title]}](#{RAW_BASE}/#{doc[:path]}): #{doc[:summary]}\n"
  end

  def build_full
    out = String.new(encoding: "UTF-8")
    out << "# Xero Kiwi — full documentation\n\n"
    out << "This file is the complete documentation for the Xero Kiwi gem (a Ruby wrapper for the Xero Accounting API), " \
           "assembled into a single document for LLM consumption. It contains the README and every doc in the docs/ " \
           "folder, in reading order.\n\n"
    out << "For the curated index version, see llms.txt in the same directory.\n\n"
    out << "Source: #{REPO}\n\n"
    DOCS.reject { |d| d[:path] == "CHANGELOG.md" }.each { |d| append_file_block(out, d[:path]) }
    out
  end

  def append_file_block(out, path)
    separator = "=" * 80
    out << "\n" << separator << "\n"
    out << "FILE: #{path}\n"
    out << separator << "\n\n"
    out << File.read(path, encoding: "UTF-8") << "\n"
  end

  # Every markdown file under docs/ has to appear in DOCS. This is the half
  # that was missing: llms-full.txt had a freshness check, but nothing
  # noticed when a new doc was never added to the list in the first place.
  def unindexed_docs
    on_disk = Dir.glob("docs/**/*.md").reject { |p| p.start_with?("docs/plans/") }
    on_disk.sort - DOCS.map { |d| d[:path] }
  end

  def outputs
    { INDEX_PATH => build_index, FULL_PATH => build_full }
  end
end
