# Proactive throttling

Xero Kiwi's retry middleware (see
[retries-and-rate-limits.md](retries-and-rate-limits.md)) handles 429s *after*
they happen — it honours `Retry-After` and backs off. That's fine when calls
are infrequent, but Xero treats *hitting* the rate limit as a misbehaviour
signal, and multi-worker setups (e.g. several Sidekiq processes syncing the
same tenant) regularly trip it.

The throttle layer is the other half of the story: block *before* the request
goes out so you rarely hit 429 in the first place. It's **opt-in** — omit
the `throttle:` kwarg and behaviour is identical to previous versions.

## When to reach for this

Wire up a limiter if:

- Multiple processes or workers can call Xero for the same tenant concurrently.
- You see sporadic 429s under normal load (not just traffic spikes).
- You want predictable pacing rather than "fire everything, react to 429s."

Skip it if you have a single-process, single-worker caller. The retry layer is
enough.

## Quick start

```ruby
require "redis"

throttle = XeroKiwi::Throttle::RedisTokenBucket.new(
  redis:      Redis.new(url: ENV["REDIS_URL"]),
  per_minute: 55,      # Xero's default is 60. Leave a bit of headroom.
  per_day:    4_900,   # optional. Xero's default is 5,000.
  max_wait:   30.0     # cap on how long we'll block for a per-minute token.
)

client = XeroKiwi::Client.new(
  access_token: access_token,
  throttle:     throttle
)

client.organisation(tenant_id)   # blocks briefly if the bucket is empty
```

Same `throttle:` instance across all clients that share a Redis — that's how
coordination happens.

## Sharing one limiter across every client (Eg. Rails)

Passing `throttle:` to every `Client.new` call gets tedious. Configure a
module-level default once, and every new client picks it up automatically:

```ruby
# config/initializers/xero_kiwi.rb
XeroKiwi.configure do |c|
  c.default_throttle = XeroKiwi::Throttle::RedisTokenBucket.new(
    redis:      Redis.new(url: ENV.fetch("REDIS_URL")),
    per_minute: 55,
    per_day:    4_900
  )
end
```

From then on:

```ruby
XeroKiwi::Client.new(access_token: token)             # uses default_throttle
XeroKiwi::Client.new(access_token: token, throttle: other) # explicit override wins
XeroKiwi::Client.new(access_token: token, throttle: XeroKiwi::Throttle::NullLimiter.new) # opt out
```

Precedence is: explicit `throttle:` kwarg → `XeroKiwi.default_throttle` →
`NullLimiter`. Reset in tests with `XeroKiwi.default_throttle = nil` so global
state doesn't leak between examples.

## How it works

A token bucket per tenant, stored as a Redis hash. Each call to Xero consumes
a token; tokens refill at `capacity / window` per millisecond. All of the
read-modify-write runs inside a Lua script, so two workers racing on the same
bucket can't both spend the same token.

The middleware reads `Xero-Tenant-Id` from the outgoing request and asks the
limiter for a token before the HTTP call goes out. Untenanted requests
(`/connections`, OAuth endpoints) bypass the middleware — they have no
bucket.

The middleware sits *below* the retry middleware in the Faraday stack, which
means every retry attempt also consumes a token. So a burst of 429s doesn't
starve other tenants' throughput.

## Composing with the retry middleware

Both layers stay on. They catch different failures:

| Layer | Fires on | Action |
|-------|----------|--------|
| Throttle (proactive) | Your own bucket count | Sleep, then retry the acquire |
| Retry (reactive) | A 429 that still slipped through | Honour `Retry-After` and retry the HTTP call |

You can't just disable the retry layer once the throttle is in place:

- Your bucket only models *your* calls to one tenant. The per-app 10k/min
  limit is shared with anything else hitting the same Xero credentials.
- Clock skew between Redis and Xero's own clock means your 60/min window
  doesn't line up perfectly with theirs.
- If Redis briefly fails, the limiter fails open (see below) — retry is the
  safety net.

## Choosing limits

Pick values *below* Xero's defaults:

| Xero limit | Headroom suggestion |
|------------|---------------------|
| 60 calls/min per tenant | `per_minute: 50` – `55` |
| 5,000 calls/day per tenant | `per_day: 4,700` – `4,900` |

The exact number depends on how much you care about the occasional 429 vs.
maximising throughput.

### What the numbers actually guarantee

This is a token bucket, so your configured value is **two things at once**:
the bucket's capacity, and its refill rate. A fresh bucket starts full, so
over the *first* window you can spend the full capacity **and** everything
that refills during it — close to double.

Measured, from a fresh bucket:

| Setting | Calls in the first 60s | Sustained after that |
|---|---|---|
| `per_minute: 55` | 109 | 55/min |
| `per_minute: 10` | 19 | 10/min |
| `per_minute: 5` | 9 | 5/min |

So `per_minute: 55` is not a promise that you will never exceed 60 in a
minute — a cold start can reach 109, and Xero will 429 some of those. The
reactive retry layer is what catches them; that's why both layers exist and
neither replaces the other.

Steady state is what the setting really controls, and there it converges on
exactly the value you configured. If you need a hard ceiling within any
single 60-second window, halve it: `per_minute: 30` keeps even a cold-start
burst under Xero's 60.

The same applies to `per_day`, on a 24-hour scale.

## Per-minute vs per-day failure modes

The two buckets fail differently on purpose.

**Per-minute:** the limiter sleeps (up to `max_wait`) and retries. Short waits
are normal and expected — a worker pausing 2 seconds to let the bucket refill
is fine. If the wait would exceed `max_wait`, it raises
`XeroKiwi::Throttle::Timeout`. Treat that as "something upstream is wrong" —
probably too many concurrent workers for the configured `per_minute`.

**Per-day:** the limiter raises `XeroKiwi::Throttle::DailyLimitExhausted`
immediately, with `retry_after` in seconds and the `tenant_id` it relates to.

`retry_after` here is **seconds, not hours**. The day bucket trickles like
the minute one rather than resetting on a boundary, so at `per_day: 4_900` a
token accrues every 17.6 seconds and that is what you get back. There is no
reset in the arithmetic.

Re-enqueueing rather than blocking is still right, but for a different
reason than the wait length. A sync needing several hundred more calls would
wait 17.6s for *each* of them — short individually, hours in aggregate. That
is the thing a worker should not sit through.

```ruby
begin
  client.invoices(tenant_id)
rescue XeroKiwi::Throttle::DailyLimitExhausted => e
  # `retry_after` is seconds until the bucket has one token — enough to
  # resume, not enough to finish. Re-enqueue rather than sleep.
  MyJob.perform_in(e.retry_after, org_id)
end
```

Don't conflate this with Xero's own `Retry-After` on a daily 429. That one
reflects Xero's limit rather than your configured one and can be genuinely
long. The two are orders of magnitude apart, so anything recording a durable
back-off should keep them distinguishable — tag the source.

Both throttle exceptions carry `tenant_id` and `retry_after`, which mirrors
the `XeroKiwi::RateLimitError` shape the retry layer raises after exhausting
retries on a 429 — so one rescue can cover both, and code handling them looks
the same.

If something outside the sync needs to know a tenant is backed off, see
[recording a durable back-off
signal](retries-and-rate-limits.md#recording-a-durable-back-off-signal).
`#remaining` is not that: it only knows about calls made through this
limiter, so a tenant another application has rate limited looks healthy to
your own bucket.

## Redis key layout

Buckets live under a namespace (`xero_kiwi:throttle` by default):

```
xero_kiwi:throttle:<tenant_id>:minute
xero_kiwi:throttle:<tenant_id>:day
```

Each key is a Redis hash with `tokens` (float) and `last_refill_ms`. Keys
carry a `PEXPIRE` of `2 × window` so stale tenants clean themselves up.

Override the namespace with `namespace:` if you're sharing a Redis with other
rate-limiter traffic:

```ruby
XeroKiwi::Throttle::RedisTokenBucket.new(
  redis:      Redis.new,
  per_minute: 55,
  namespace:  "myapp:xero"
)
```

## What happens if Redis is down

The limiter fails open. If Redis raises (connection refused, timeout), the
limiter logs a warning via `Kernel.warn` and returns immediately so the
request still goes out. The retry middleware will still catch any 429s that
result.

Pass a `logger:` to route warnings somewhere useful:

```ruby
XeroKiwi::Throttle::RedisTokenBucket.new(
  redis:      Redis.new,
  per_minute: 55,
  logger:     Rails.logger
)
```

Fail-open is deliberate: a misbehaving Redis shouldn't stop your app talking
to Xero. The reactive retry layer still protects you from actually hitting
the limits.

## Asking how much is left

`RedisTokenBucket#remaining(tenant_id)` reports the current token counts
without spending one:

```ruby
bucket.remaining("tenant-abc")
# => { minute: 55, day: 4_312 }
```

It runs the same refill arithmetic as `acquire` in a separate read-only
Lua script, so polling it can't starve the bucket you're polling. Like
`acquire`, it fails open and returns `nil` if Redis is unreachable, and
`day` is `nil` when no `per_day` limit is configured.

Most callers won't use this directly — `client.rate_limit(tenant_id)`
combines it with what Xero itself reported and hands back whichever is
stricter. See [retries and rate limits](retries-and-rate-limits.md).

## Writing a custom limiter

The limiter contract is one required method:

```ruby
class MyLimiter
  def acquire(tenant_id)
    # Block until a token is available for this tenant, or raise
    # XeroKiwi::Throttle::Timeout / DailyLimitExhausted if you want the
    # same exception shapes.
  end

  # Optional. Implement it and client.rate_limit(tenant_id) will factor
  # your bucket into its answer; leave it out and kiwi falls back to
  # Xero's reported headers alone.
  def remaining(tenant_id)
    { minute: …, day: … }
  end
end
```

Pass any object implementing it as `throttle:`. The built-in
`XeroKiwi::Throttle::NullLimiter` is a no-op default — it's what runs when
`throttle:` is omitted.
