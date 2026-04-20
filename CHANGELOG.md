## [Unreleased]

## [0.4.0] - 2026-04-20

### Added

- `XeroKiwi.default_throttle` + `XeroKiwi.configure { |c| c.default_throttle = ... }` for configuring one shared throttle limiter at the module level. New `Client` instances pick it up automatically when no `throttle:` kwarg is passed, so a Rails app can wire a single `RedisTokenBucket` in an initializer instead of threading it through every call site. Per-instance `throttle:` still overrides. See `docs/throttling.md`.

## [0.3.0] - 2026-04-20

### Added

- Every accounting list endpoint (`contacts`, `invoices`, `credit_notes`, `overpayments`, `prepayments`, `payments`, `users`, `branding_themes`, `contact_groups`) now accepts `where:`, `order:`, `page:`, and `modified_since:` kwargs. `where:` and `order:` take a typed Hash (field-name-aware, safe literal formatting) or a raw String (escape hatch). `page:` maps to Xero's `page` query param. `modified_since: Time` sends `If-Modified-Since`; a `304 Not Modified` response returns an empty `Page`. See `docs/querying.md`.
- New `XeroKiwi::Page` return type for every list method — `Enumerable` with `size` / `empty?` / `to_a` / `page` / `page_size` / `item_count` / `total_count`.
- Lazy `each_<resource>` helpers (`each_invoice`, `each_contact`, `each_payment`, `each_credit_note`, `each_prepayment`, `each_overpayment`, `each_branding_theme`, `each_contact_group`, `each_user`) that walk every page for whole-tenant scans or incremental syncs. Returns an `Enumerator` when no block is given.
- `attribute` DSL gains a `query: true` kwarg; `identity` attributes are auto-included in the resource's `query_fields` schema so you rarely need `query: true` on IDs.

### Breaking

- List methods now return `XeroKiwi::Page`, not `Array`. `Page` is `Enumerable` + `size` / `empty?` / `to_a`, so `.each`, `.map`, `.first`, `.count`, `.select`, `.find` keep working. Callers relying on raw `Array` behaviour (`<<`, `[0..2]`, `push`, mutation, `JSON.dump(page)`, `page.is_a?(Array)`) should call `.to_a`.

### Fixed

- `ResponseHandler` now lets `304 Not Modified` through instead of raising.

## [0.2.1] - 2026-04-17

### Changed

- Internal refactor of the accounting resource classes. Each resource now declares its fields through a shared `attribute` DSL (`lib/xero_kiwi/accounting/resource.rb`) rather than an `ATTRIBUTES` constant + hand-written `initialize`. Hydration logic (including the `/Date(ms)/` and ISO 8601 parsing previously duplicated across nine files) lives in a single `XeroKiwi::Accounting::Hydrator` module. The mixin also provides default `==` / `eql?` / `hash` (via an `identity :xxx_id` declaration for resources with a server-side primary key, structural `to_h`-based otherwise) and an ActiveRecord-style `inspect` that shows every attribute inline — nested objects collapse to a one-line reference and collections to a `[N items]` summary. No public API changes — constructor signatures and return types are preserved.

## [0.2.0] - 2026-04-15

### Added

- Optional proactive rate-limit throttling via a Redis-backed token bucket, keyed per tenant. Pass `throttle:` to `XeroKiwi::Client.new` to coordinate rate limits across processes (e.g. multiple Sidekiq workers hitting the same Xero tenant). Supports per-minute and per-day limits; per-minute waits are bounded by `max_wait`, per-day exhaustion raises `XeroKiwi::Throttle::DailyLimitExhausted`. Composes with the existing reactive retry layer — neither replaces the other. See `docs/throttling.md`.

### Changed

- `redis` is now a runtime dependency (used only if you opt into throttling).

## [0.1.1] - 2026-04-15

- Add `lib/xero-kiwi.rb` shim so `gem "xero-kiwi"` in a Gemfile auto-requires the gem without needing `require: "xero_kiwi"`.

## [0.1.0] - 2026-04-15

- Initial release
