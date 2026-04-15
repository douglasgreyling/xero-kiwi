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
maximising throughput. If your job batches run for hours, lean conservative —
the daily limit resets on Xero's clock, not yours, and the first few
minutes after "daily reset" can be ambiguous.

## Per-minute vs per-day failure modes

The two buckets fail differently on purpose.

**Per-minute:** the limiter sleeps (up to `max_wait`) and retries. Short waits
are normal and expected — a worker pausing 2 seconds to let the bucket refill
is fine. If the wait would exceed `max_wait`, it raises
`XeroKiwi::Throttle::Timeout`. Treat that as "something upstream is wrong" —
probably too many concurrent workers for the configured `per_minute`.

**Per-day:** the limiter raises `XeroKiwi::Throttle::DailyLimitExhausted`
immediately, with a `retry_after` attribute in seconds. Sleeping for hours is
never the right move in a Sidekiq worker, so the caller has to decide:

```ruby
begin
  client.invoices(tenant_id)
rescue XeroKiwi::Throttle::DailyLimitExhausted => e
  # Re-enqueue the job for tomorrow. `retry_after` is seconds until the
  # bucket has at least one token.
  MyJob.perform_in(e.retry_after, org_id)
end
```

This mirrors the `XeroKiwi::RateLimitError` shape that the retry layer raises
after exhausting retries on a 429, so the handling code is familiar.

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

## Writing a custom limiter

The limiter contract is one method:

```ruby
class MyLimiter
  def acquire(tenant_id)
    # Block until a token is available for this tenant, or raise
    # XeroKiwi::Throttle::Timeout / DailyLimitExhausted if you want the
    # same exception shapes.
  end
end
```

Pass any object implementing it as `throttle:`. The built-in
`XeroKiwi::Throttle::NullLimiter` is a no-op default — it's what runs when
`throttle:` is omitted.
