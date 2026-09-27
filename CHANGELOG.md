## [Unreleased]

### Added

- `RateLimitError`, `Throttle::DailyLimitExhausted` and `Throttle::Timeout` now carry the **`tenant_id`** they relate to, and `Throttle::Timeout` also carries **`retry_after`** (it previously carried nothing at all). A caller recording a durable back-off signal — "this tenant is paused until T, because X" — now gets every fact from the exception instead of inferring the tenant from surrounding context, which breaks as soon as one client serves more than one tenant. `docs/retries-and-rate-limits.md` gains a section on the pattern.
- Documented that `client.rate_limit` is **process-local**. The reported figures live in memory on the `Client` that made the request, so a worker's reading dies with the job. That is fine for "should this loop stop early?", which is what it is for, and is not a way to tell a web request that a tenant is backed off.

## [0.6.0] - 2026-09-27

### Fixed

- **`Accounting::Allocation#amount` always returned nil.** It was mapped to Xero's `"Amount"`, which is the key for the allocation *request* body. Every response — and allocations only ever reach this gem embedded in a CreditNote, Prepayment or Overpayment response — carries `"AppliedAmount"`. The allocated value is now modelled as **`applied_amount`**, and `#amount` is an alias of it so callers who reached for the obvious name get the value they meant. Nothing that depended on a real value is affected, because there was never one to depend on.

  This mattered more than a missing field usually would: `allocations.map(&:amount)` returned an array of nils rather than raising, so an importer would have written zeroes into every allocated amount with nothing failing anywhere. Reported by a consumer who checked stored payloads before trusting the typed path.

  Four spec files had fabricated `"Amount"` payloads and so agreed with the bug instead of catching it; all now use the real response shape.

### Breaking

- `Allocation#to_h` now carries `:applied_amount` instead of `:amount`, and `:amount` is no longer a declared attribute (it is a plain reader, so one value maps to one key). Anyone reading `to_h[:amount]` was reading nil.

### Documentation

- The README now documents the release process. It covered running specs but said nothing about cutting a release, so the sequencing lived only in one person's head. It leads with the rule and the reason — `rake release` tags whatever is checked out, so a version bump riding along in a pull request gets orphaned the moment that PR is squash-merged, which is what happened to v0.5.2 — and records the thing that is not guessable from the repo: `docs/` ships inside the gem, so a documentation-only fix still needs a patch release to reach anyone.

## [0.5.2] - 2026-09-27

### Documentation

- Documented that `Resource#raw` returns nil on nested objects (line items, addresses, contact persons, payment terms) even with `retain_raw: true`, and that the enclosing resource's hash is the access path — `org.raw["Addresses"]` rather than `org.addresses.map(&:raw)`. The behaviour was deliberate and explained in a comment on `from_response`, but the `#raw` docstring never mentioned it and the failure is a silent nil, so a consumer mapped over a nested collection and was one step from storing `[null]`.
- Added a written contract for `raw` in `docs/client.md`: it is the parsed JSON with only top-level keys stringified, kiwi never normalises it (absent keys stay absent rather than becoming `[]`), unmodelled keys are preserved, and the freeze is shallow — the hash is frozen, the structures inside it are not. Specs pin all four, plus the nested-nil behaviour. The previous "is frozen" example overstated the guarantee and has been replaced.
- `llms.txt` is now generated alongside `llms-full.txt` from a single manifest in `tasks/llms.rb`, rather than hand-maintained. It had not been touched since the initial commit and was missing four releases of material — no `querying.md`, no `throttling.md`, no `tracking-category.md`, and no mention of `Page`, `RateLimit`, the throttle limiters or the tracking classes. `rake llms:check` now also fails when a doc exists under `docs/` that the manifest does not list, which is the half that was missing: the freshness check could not notice a doc that was never indexed in the first place.

## [0.5.1] - 2026-09-26

### Documentation

- Pinned down the scope of `Resource#raw`, which was ambiguous enough to mislead a real consumer. It holds the resource's own item hash — `contact.raw` has no `"Contacts"` key — and it is the JSON representation specifically. Xero's XML representation nests differently (no arrays, so one child parses to a Hash and several to an Array), so `raw` cannot reproduce an XML-derived shape. `docs/client.md` gains a short migration section covering what that means for anyone replacing a client that sent `Accept: text/xml` and has stored payloads. Specs added for both the envelope scope and the PascalCase/snake_case split. The migration section sorts readers into the two piles that behave differently: ones that dig the XML-only structure and must change, and ones that already normalise (`[value].flatten.compact`) where only the writer changes and stored rows stay readable.

## [0.5.0] - 2026-09-26

The sync-support release: everything needed to drive a full-tenant sync through kiwi rather than around it.

### Added

- **`page_size:`** on every list method, plus a client-level default (`Client.new(page_size: 1_000)`) that per-call overrides beat. Maps to Xero's `pageSize`. Unset means the parameter is omitted and Xero applies its own default of 100, so existing callers are unaffected. Worth setting for any full sync — at 100 per page a 50,000-invoice tenant costs ~500 API calls against a 5,000/day limit; at 1,000 it costs ~50.
- **`each_<resource>_page`** for all ten list resources, yielding a whole `XeroKiwi::Page` rather than its items — so the page number reaches the caller, which is what a resumable sync needs to record.
- **`start_page:`** on both `each_<resource>` and `each_<resource>_page` (default 1), so a resumed run picks up where the last one stopped.
- **`include_archived:`** on `contacts` / `each_contact` / `each_contact_page`. A distinct query parameter, not a `where` filter: filtering on `contact_status` returns *only* archived contacts, where this returns both kinds in one pass.
- **`Resource#raw`** — Xero's untouched response hash, behind `Client.new(retain_raw: true)`. Off by default because retaining it roughly doubles the memory of a large page. Populated on resources built directly from a response, not on nested objects; the top-level hash already holds every nested payload, so `contact.raw["ContactPersons"]` gets there. Note `#raw` is not `#to_h` — `to_h` is a snake_case projection with different keys and different nesting.
- **`client.rate_limit(tenant_id)`** returning a `XeroKiwi::RateLimit`. Blends what Xero's headers last reported for that tenant with what the configured throttle bucket holds, and reports **the stricter of the two** — a configured limit is a ceiling you chose, a reported limit is reality. Exposes `day_remaining`, `minute_remaining`, `day_below?`, `minute_below?`, `day_source`, `minute_source`, `reported`, `configured` and `known?`. Headers are captured on every response including errors, since a 429 is when they matter most. With nothing known, `day_below?` returns false — not knowing isn't a reason to halt a sync.
- **`RedisTokenBucket#remaining(key)`** — current token counts without spending one, via a separate read-only Lua script. `#remaining` is an optional part of the limiter contract; `Client` checks `respond_to?` first, so a custom limiter written against 0.2.0 keeps working.
- **Tracking categories**: `client.tracking_categories`, `client.tracking_category`, `each_tracking_category` and `each_tracking_category_page`, with a new `Accounting::TrackingOption` for the nested `Options` array. See `docs/accounting/tracking-category.md`.
- `XeroKiwi::Page#reported_page_size` — the page size Xero actually stated, or nil when the response carried no `pagination` envelope. `page_size` keeps its existing fallback to the item count.

### Breaking

- **`Accounting::TrackingCategory` is now the `/TrackingCategories` endpoint resource** (`tracking_category_id`, `name`, `status`, `options`). The flattened category-and-chosen-option pair nested on line items and contacts — which this class used to model — is now **`Accounting::Tracking`**, matching Xero's own field name for it. Update any reference to `XeroKiwi::Accounting::TrackingCategory` that came from `line_item.tracking` or a contact's tracking collections. The two shapes share a name and one ID field and nothing else, which is why they're now separate classes.

### Fixed

- Page walks no longer fetch a redundant empty page. `build_page` falls back to the item count when Xero returns no `pagination` envelope, which made the walker's short-page check compare a number to itself (`items.size < items.size`) and never fire, leaving `empty?` as the only way to stop. The walk now measures against Xero's stated page size when there is one and the largest page seen so far otherwise — deliberately **not** against the requested `page_size`, since Xero clamps a request above an endpoint's maximum and a walk that asked for 2,000 where the cap is 1,000 would have seen page 1 as short and truncated the sync.

### Changed

- Widened the `jwt` runtime constraint to `>= 2.7, < 4.0` and `redis` to `>= 5.0, < 7.0`. Both majors (`jwt` 3.x, `redis` 6.x) pass the full suite, including the Lua-backed throttle specs against a real Redis. Widening rather than bumping means a host app on `redis` 5 (Sidekiq, Rails cache) isn't forced to move in lockstep with this gem.
- Dropped the unused `mock_redis` development dependency. The throttle's bucket maths runs as a server-side Lua script, so the specs have always used a real Redis — `mock_redis` was only ever named in the comments explaining why it couldn't be used, and its `redis (~> 5)` runtime pin blocked resolving `redis` 6.

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
