## [Unreleased]

### Breaking

- **Money attributes now return `BigDecimal` instead of `Float`.** Xero sends money as a JSON number, so Ruby parsed it into a Float and the `:decimal` type declaration passed it straight through, doing nothing. Floats cannot represent most decimal fractions, so arithmetic between two money fields drifts while each one still prints correctly:

  ```ruby
  17228.67 + 2584.3   # => 19812.969999999998, where Xero's Total is 19812.97
  ```

  Measured against the recorded `invoices/list` response, `sub_total + total_tax == total` failed on **3 of 55 invoices** as Floats and on **none** as BigDecimals. Every individual value round-trips exactly — all 111 distinct money literals in that recording — so the failure only appears once you do arithmetic, which is what makes it quiet.

  Applies to all 36 `:decimal` attributes across `Invoice`, `CreditNote`, `Prepayment`, `Overpayment`, `Payment`, `Allocation` and `LineItem`. Floats and Integers convert via `#to_d`, which uses the shortest decimal that round-trips, so BigDecimal holds the number Xero wrote rather than the binary approximation of it. Numeric strings are parsed with `BigDecimal()` rather than `String#to_d`, because `to_d` answers `0.0` for unparseable input and a silent zero in a money field is the failure this gem has shipped twice. Unparseable input reads as `nil`, as it does for `:date`.

  Upgrading: comparison is not a concern — `BigDecimal("19812.97")` equals the Float `19812.97`, and a `decimal`/`numeric` column takes it unchanged. A consumer verified that last point on real data, passing five money fields straight into decimal columns with no conversion and getting identical rows.

  Two things do change. `to_s` gives `"0.1981297e5"` rather than `"19812.97"` (use `to_s("F")`), and `to_json` gives that same scientific-notation **string** where a Float gave a JSON number — a visible change in shape if you write a **typed** money attribute into a `jsonb` column. **`raw` is unaffected**: it holds Xero's parsed payload untouched, so money in there is still a Float and still serialises as a JSON number. `#inspect` renders decimals in plain form, so debugging output is unaffected.

  **Check for `.to_f` on money you persist.** It silently undoes this change, and a `decimal(19,4)` column holds more precision than a Float can carry — `BigDecimal("1234567890123.4567").to_f` round-trips to `1234567890123.456`. Out of reach for GBP or ZAR at ordinary invoice sizes, not for IDR or VND. A `.to_f` left over from an XML-era client, where the value arrived as a String, is where to look.

- **`""` now reads as `nil` on `:decimal` attributes too.** 0.8.0 normalised empty strings on `:string`, `:enum` and `:guid` and explicitly left `:decimal` alone as wanting its own decision. This is that decision. The alternative was `BigDecimal("")` raising, or a silent zero — the same shape as both allocation regressions.

- **Removed `Invoice#sales_tax_calculation_type_code`.** It read the payload key `"SalesTaxCalculationTypeCode"`, which appears in none of this gem's recorded responses, nowhere in Xero's 911K OpenAPI spec, and in none of a consumer's 368 recorded interactions across both the XML and JSON eras. Xero has no invoice-level sales-tax-calculation field under any name; its US sales tax fields are on the line item. The reader has returned `nil` since the first commit.

  Removing it cannot break working code, because there has never been a value to depend on. It is listed as Breaking because the method disappears: a caller reading it goes from a silent `nil` to a `NoMethodError`, which is the same trade the empty-string change made in 0.8.0. If Xero ever does send the key, `retain_raw: true` exposes it through `invoice.raw`.

  Recording why it went, so nobody re-adds it from the same plausible-sounding guess: it was never verified against a payload or a schema, and it was documented as "US auto sales tax calculation type", which made a permanent `nil` read as an answer about the organisation rather than a gap in the gem.

### Fixed

- **`invoice.credit_notes`, `invoice.prepayments` and `invoice.overpayments` returned objects with the applied amount missing.** Xero nests **allocation stubs** under an invoice, not whole documents: a stub carries `AppliedAmount`, the amount applied to *that* invoice. Nothing modelled that key, so the nearest-looking reader was `total` — the document's own total, and a different number on **19 of the 24 stubs** in the recorded response. On one, `total` was `10983.65` where `applied_amount` was `857.35`.

  All three resources now model `applied_amount`. It is `nil` on a document fetched in its own right, where Xero sends no such key, and populated on every stub in the recording. The only route to it before was `invoice.raw["CreditNotes"]` with `retain_raw: true`, since nested objects carry no `#raw`.

  Found by the coverage task below rather than by comparison or by reading Xero's docs — the key is in no doc table, because the docs describe the XML representation and this shape only exists in JSON.

- **`LineItem#account_id` was reading a key Xero does not send.** It mapped to `"AccountId"`; Xero sends `"AccountID"`, so the attribute was `nil` on every line item ever returned. The string `AccountId` appears **zero times** in Xero's 911K OpenAPI spec, and a consumer's recorded JSON response carries `AccountID` on all 18 of its populated line items.

  No recording in this repo could have caught it: list endpoints omit line items, so `LineItem` has never had a real payload here. It was found by comparing the classes against Xero's published spec, which is now `rake xero:schema`.

### Added

- `Accounting::Organisation` now models `tax_number_name`, which names what the organisation's locale calls its tax number (`"VAT Number"` on the recorded tenant). Present and populated in the recording, previously reachable only through `raw`.

- Fields Xero's spec documents and the recordings confirm on every record, all previously reachable only through `raw`: `Invoice#is_discounted`, `Invoice#has_errors`, `CreditNote#has_errors`, `CreditNote#invoice_addresses`, `Contact#has_validation_errors`, `Payment#has_validation_errors`, `ContactGroup#has_validation_errors`, and `Prepayment#branding_theme_id`.

- **`attribute` accepts several candidate keys**, as `xero: %w[TrackingCategoryOption TrackingOptionName]`. The first one present in the payload wins. It is for a field with no recorded payload to settle which key Xero sends: a wrong single key reads `nil` forever and is indistinguishable from a field the tenant never fills, which is how two regressions shipped. `Contact#tracking_option_name` uses it — Xero's spec calls that field `TrackingCategoryOption`, kiwi called it `TrackingOptionName`, and neither spelling appears in any recording because no tenant to hand has a contact-level tracking default.

- **`rake xero:schema`** compares the resource classes against Xero's published OpenAPI spec, cached for a day. It is the other half of `xero:coverage`: a recording shows what one tenant populated, the spec shows what an endpoint can return at all. Each has caught what the other missed — the spec found the `AccountID` bug that no payload here could, and the recordings hold `User#GlobalUserID`, which the spec omits entirely and whose absence emptied a consumer's memberships table.

  It reports rather than fails, for the same reason `xero:coverage` does, and because the spec is not authoritative on its own: it documents `CreditNote#DueDate`, which Xero sends on none of the 18 recorded credit notes, and omits the four `TrackingOption` booleans that a live capture proved real. Treat a difference as a question; a payload settles it where one exists.

- **`rake xero:coverage`** compares every recorded response against the resource classes that model it, and reports keys Xero sends that nothing reads, attributes nil in every recording, declared types that disagree with what arrived, and classes no recording exercises. Every silent bug this gem has shipped would have appeared in one of those four lists, with the disproving payload already committed. It reports rather than fails: gating it would need an allowlist of legitimately-absent keys, and an allowlist becomes a list nobody reads.

  It also names the blind spot, and distinguishes *no cassette here* from *unverified*, which are not the same thing. `LineItem`, `TrackingCategory` and `TrackingOption` have no cassette in this repo but have each been checked against a real response elsewhere — the task now says so, and says which. Only `Tracking` and `ExternalLink` are genuinely unverified: no payload anywhere has carried a populated instance.

  The walk also descends into attributes that hydrate through a custom lambda, which it previously skipped. `PaymentTerms` and `PaymentTerm` had read as exercised by nothing while a recorded contact carried both, and the type check immediately showed `PaymentTerm#day` arriving as an Integer against a `:string` declaration. Those attributes now declare `of:` purely so the audit can find the class; `Hydrator` ignores it when `hydrate:` is set.

### Documentation

- Money attribute types were documented three different ways for the same field — `String` on Overpayment and Prepayment, `Numeric` on CreditNote and Payment, `String/Numeric` on Invoice — and three examples showed `total # => "100.00"`, a quoted string it never was. All 32 rows now say `BigDecimal`, generated from the attribute declarations so they cannot drift apart again.

- Each of Credit Note, Prepayment and Overpayment gained a **Nested under an invoice** section covering the stub shape, with the figures taken from the recorded response rather than invented.

- `docs/client.md` documents money as a fourth thing to check when migrating from an XML client, alongside the existing nesting, key-name and type axes.

## [0.9.0] - 2026-09-29

### Added

- `Accounting::CreditNote` now models `payments`, which `Prepayment` and `Overpayment` both already did. Found by the asymmetry rather than by any payload comparison — four sibling resources, one missing a field, visible from the class definitions alone. The recorded `credit_notes/list` response carries `Payments` on all seventeen records, with data on two.
- `Accounting::Prepayment` now models `reference`, which every comparable resource already did — `CreditNote`, `Overpayment`, `Invoice` and `Payment` all carry it. Confirmed against the recorded `prepayments/list` response: `Reference` is present on all nine records, with real values.

  It was twice dismissed as a non-gap, including by me, on the strength of stored XML-era rows where the key was absent. That is the same mistake as the allocation regression — XML-derived data answering a question about JSON — and this time the JSON was already committed in `spec/fixtures` and went unread again. The recorded spec now asserts it.

### Documentation

- Added the four value-object docs — Address, Phone, ExternalLink, PaymentTerms — to the README's documentation table. They existed, were in the `llms.txt` manifest and were reachable from the generated bundles, while being invisible to anyone reading the README. `rake llms:check` now fails when a doc in the manifest is not linked from the README, which is the third index to get a drift guard.

## [0.8.0] - 2026-09-29

### Breaking

- **Empty strings from Xero now read as `nil` on modelled attributes.** Xero sends `""` for a text field with no value, where its XML representation produced `nil`. Left as `""` it reaches a database column and quietly changes what queries match — a consumer's `where.not(xero_logo_url: nil)` started matching themes with no logo, and was one step from putting a blank image into customer statements.

  Applies to `:string`, `:enum` and `:guid` attributes. `:date` has always behaved this way, so strings doing otherwise was an inconsistency rather than a principle. `:bool` and `:decimal` are untouched — there is no evidence Xero sends `""` for a numeric field, and that would want its own decision.

  Only exactly `""` is affected. `" "` is left alone, because trimming it would be editorialising on a value rather than recognising an absent one. **`raw` is untouched** and still holds `""` verbatim, so the original payload is always recoverable.

  Upgrading: code that chains off a string attribute without a guard (`contact.email_address.downcase`) will now raise `NoMethodError` where it silently operated on `""`. That is the intended trade — silent is the failure mode this release exists to remove.

  Where to actually look: **optional text fields** — references, logo URLs, email addresses, invoice numbers — since those are the ones Xero leaves empty. Enums and IDs are effectively unaffected in practice because Xero always populates them, and code reading those tends to fail loudly either way (`hash.fetch("".downcase)` already raised `KeyError`; it now raises `NoMethodError` and loses the field name from the message). One consumer measured 14 unguarded `.downcase` calls against this change and needed no code changes at all.

### Fixed

- `RateLimitCapture` now finds Xero's quota headers whatever case they arrive in. Faraday's own header container is case-insensitive so production was never affected, but a plain Hash is not, and Xero's headers are cased differently depending on who recorded them — a VCR cassette holds `X-Daylimit-Remaining`, not `X-DayLimit-Remaining`. Missing them records nothing, and `day_below?` answers false when nothing is known, so the failure would have been a quota check that passes while measuring nothing. Spotted by a consumer reading their own recorded cassettes against the lookup.

- **`Allocation#applied_amount` was nil for every allocation — 0.6.0 fixed the name and kept the bug.** Xero sends the allocated value under `"Amount"` in JSON and `"AppliedAmount"` in XML. 0.6.0 concluded the opposite, from payloads a legacy XML client had stored, and remapped the attribute to a key this JSON-only client never receives. Before 0.6.0 the mapping was right. Measured on a live tenant: 24 of 24 allocations carry `Amount`, none carry `AppliedAmount`, on both the list and single-resource endpoints.

  Both keys are now modelled and **both `#amount` and `#applied_amount` resolve to whichever one arrived**, so neither can be nil while the other holds a value. This has been got wrong twice in opposite directions, each time producing a nil that an importer coerced to `0.0` and stored with nothing raising; reading both is cheaper than being certain. `to_h` reports the value under both keys, and `raw` still shows which key Xero sent.

### Added

- `Accounting::User` now models **`global_user_id`** (`GlobalUserID`). Xero returns two identifiers that differ for every user: `user_id` is scoped to the organisation, `global_user_id` identifies the person across all of them and is what an OIDC `id_token` subject corresponds to. A consumer keyed membership records on `user_id` while its own user table used `GlobalUserID`, so every membership pointed at an identifier no user row carried — the association came back empty, silently, with the right count and the right roles.

- `Accounting::TrackingOption` now models the four booleans Xero returns alongside `Status`: `is_active`, `is_archived`, `is_deleted` and `has_validation_errors`. Confirmed against a live `GET /TrackingCategories` response — every key the endpoint returns on an option is now modelled. `#active?` still reads `status`, because the two agree on an active option and whether they diverge on an archived one is unconfirmed; `is_archived` and `is_deleted` are the ones to read when you need to tell those apart, since `status` collapses both into `"DELETED"`.

### Documentation

- **Corrected what `Throttle::DailyLimitExhausted#retry_after` actually means.** Its docstring said the wait was "typically measured in hours" and described a reset boundary. The day bucket trickles like the minute bucket — `capacity / window_ms` per millisecond — so at `per_day: 4_900` a token accrues every 17.6 seconds, and that is what `retry_after` returns. There is no reset in the arithmetic. Reported by a consumer who read the comment, believed the wait would be hours, and designed an hourly sweep around it before measuring.

  Re-enqueueing rather than blocking is still correct, but for a different reason than the docstring gave: a sync needing several hundred more calls waits 17.6s for each of them, which is hours in aggregate even though each wait is short.

- **Documented what `per_minute` and `per_day` actually guarantee.** A token bucket's configured value is both its capacity and its refill rate, and a fresh bucket starts full — so the first window can spend the capacity *and* everything refilling during it. Measured: `per_minute: 55` allows **109 calls in the first 60 seconds**, not 55. The `Choosing limits` table recommends exactly that value as headroom under Xero's 60, which it is not at a cold start; steady state does converge on the configured rate. Halve the value if you need a hard ceiling in any single window. Both behaviours now have specs so a future change is deliberate.

- Noted that the two `retry_after` sources are orders of magnitude apart — Xero's reported wait on a daily 429 can be long, while `DailyLimitExhausted` is always seconds — and that anything recording a durable back-off should tag which one it came from.
- Strengthened the XML-migration guidance in `docs/client.md` to cover **type** divergence, which it previously called "usually fine". XML has no types, so a boolean arrives as the string `"false"` — truthy in Ruby — while JSON sends a real `false`. A reader using plain truthiness rather than a cast has been doing the opposite of what it reads as, and moving to kiwi silently reverses it at cutover. Reported by a consumer who found years of statements going to contact people explicitly marked not to receive them. That is now the third documented axis of divergence, after nesting and key names.

## [0.7.0] - 2026-09-27

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
