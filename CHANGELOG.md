## [Unreleased]

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
