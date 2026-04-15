# Retries and rate limits

This doc explains how Xero Kiwi handles transient failures: rate limiting, server
errors, and network blips. Most of the time you don't need to know any of
this — the defaults are sensible. Read on if you need to tune the retry
policy or you want to understand what's happening when a request mysteriously
takes 4 seconds.

## Xero's rate limits

Xero enforces three separate rate limits, all returned with HTTP 429:

| Limit | Default | Header indicator |
|-------|---------|------------------|
| Per-minute (per tenant) | 60 calls | `X-Rate-Limit-Problem: minute` |
| Daily (per tenant) | 5,000 calls | `X-Rate-Limit-Problem: day` |
| Per-app per-minute | 10,000 calls | `X-Rate-Limit-Problem: appminute` |
| Concurrent | 10 simultaneous requests | (no specific problem header) |

Plus a `Retry-After` header on every 429 telling you how many seconds to
wait before trying again.

## What Xero Kiwi does automatically

Xero Kiwi sets up a `faraday-retry` middleware that handles transient failures
without any code from you. The default retry policy:

| Setting | Default | Why |
|---------|---------|-----|
| `max` | 4 retries | High enough to ride out most rate-limit pauses, low enough to fail fast on real outages. |
| `interval` | 0.5 s | Initial wait. |
| `backoff_factor` | 2 | Exponential backoff. So waits are roughly 0.5s, 1s, 2s, 4s. |
| `interval_randomness` | 0.5 | ±50% jitter on each wait, so a herd of clients doesn't refresh in lockstep. |
| `retry_statuses` | `[429, 502, 503, 504]` | Statuses that get retried. |
| `methods` | All HTTP methods | Including POST/PUT/DELETE. (Xero's idempotency makes this safe.) |
| `exceptions` | `Faraday::ConnectionFailed`, `Faraday::TimeoutError`, `Faraday::RetriableResponse`, `Errno::ETIMEDOUT` | Transport-level failures that get retried. |

### Retry-After is honoured

`faraday-retry` automatically respects the `Retry-After` header on 429
responses. So if Xero says "wait 30 seconds," Xero Kiwi waits 30 seconds before
retrying — not the exponential backoff schedule. This is the whole reason
to use a real retry middleware instead of rolling your own.

### Which 5xx are retried

Xero Kiwi retries `502 Bad Gateway`, `503 Service Unavailable`, and `504 Gateway
Timeout`. These are the canonical "the upstream is having a temporary
problem" statuses.

**500 Internal Server Error is deliberately NOT retried.** A 500 usually
means Xero hit a real bug in handling your request — retrying the same
request will give the same 500. If you want to retry 500s in your own
code, catch `XeroKiwi::ServerError` and handle it explicitly.

### What happens after retries are exhausted

| Scenario | Final exception |
|----------|-----------------|
| All retries returned 429 | `XeroKiwi::RateLimitError` (with `retry_after` and `problem` attributes) |
| All retries returned 502/503/504 | `XeroKiwi::ServerError` |
| All retries failed at the transport level | The underlying `Faraday::ConnectionFailed` / `Faraday::TimeoutError` |

The retried request count includes the original attempt, so `max: 4` means
**up to 5 total HTTP requests** before giving up.

## Customising the retry policy

Pass `retry_options:` to `XeroKiwi::Client.new`. The hash is merged into Xero Kiwi's
defaults, so you only specify what you want to change:

```ruby
client = XeroKiwi::Client.new(
  access_token: "...",
  retry_options: {
    max:      8,    # try up to 8 retries
    interval: 1.0   # initial 1s wait instead of 0.5s
  }
)
```

### Common customisations

**Aggressive retries for batch jobs that can wait:**

```ruby
retry_options: {
  max:            10,
  interval:       2.0,
  backoff_factor: 2
}
# Waits up to ~17 minutes total (2, 4, 8, 16, 32, 64, 128, 256, 512, 1024 seconds)
```

**No retries (e.g. for tests):**

```ruby
retry_options: { max: 0 }
```

**Tight retries with no jitter (also for tests):**

```ruby
retry_options: {
  max:                 2,
  interval:            0,
  interval_randomness: 0,
  backoff_factor:      1
}
```

This is what Xero Kiwi's own test suite uses to keep specs deterministic and
fast.

**Adding 500 to the retry list** (against my advice, but sometimes you
have a known-flaky upstream):

```ruby
retry_options: {
  retry_statuses: [429, 500, 502, 503, 504]
}
```

### One thing you must NOT remove

Xero Kiwi's default `exceptions:` list includes `Faraday::RetriableResponse`,
which is the *internal* signal `faraday-retry` uses to flag a status-code
retry. **It must stay in the list**, or the retry middleware can't catch
its own retry signal and 429s/503s will never be retried — they'll bubble
straight up as raw `Faraday::RetriableResponse` exceptions.

If you override `exceptions:`, make sure to include the four defaults:

```ruby
retry_options: {
  exceptions: [
    Faraday::ConnectionFailed,
    Faraday::TimeoutError,
    Faraday::RetriableResponse, # ← critical
    Errno::ETIMEDOUT,
    MyOwnException               # add your own
  ]
}
```

In practice, you almost never need to override this list — the defaults
cover everything Xero will throw at you.

## How the middleware stack is wired

The order of Faraday middleware matters and was the source of one nasty
bug during development. The chain looks like this:

```
ResponseHandler  ← outermost, catches errors AFTER retries are exhausted
↓
Retry           ← retries 429/503/etc on the way back, respects Retry-After
↓
JSON            ← parses response bodies
↓
Adapter         ← actually makes the HTTP call
```

The trick is putting **`ResponseHandler` outside `Retry`**. If they were the
other way round, a 429 would go: adapter returns env → JSON parses →
ResponseHandler raises `RateLimitError` → Retry catches the exception →
needs to know about `RateLimitError` to know to retry it. That's brittle.

By putting Retry on the inside, the retry middleware sees raw HTTP envs
with status 429 and uses its own `retry_statuses` config to decide what to
do. ResponseHandler only sees the *final* env (after retries are done) and
maps it to a Xero Kiwi exception.

You don't need to think about any of this — it's the gem's job — but if
you ever subclass the client or insert your own middleware, this is the
ordering to preserve.

## Token refresh on 401

Token refresh isn't part of the retry middleware — it's handled separately
by `XeroKiwi::Client#with_authenticated_request` (see [Client — request
lifecycle](client.md#the-request-lifecycle)). The two systems compose
cleanly:

1. Client wraps the call in `with_authenticated_request`.
2. The retry middleware retries 429/503 inside the wrapper.
3. If retries are exhausted with a 401, ResponseHandler raises
   `AuthenticationError`.
4. `with_authenticated_request` catches it, refreshes the token, and
   retries the *outer* call exactly once.

Crucially, step 4 retries the **whole call**, including the retry
middleware. So a single API call can trigger up to `max + 1` HTTP attempts
*twice*: once before the refresh, once after.

## Concurrency notes

The retry middleware is per-request, not per-client, so multiple concurrent
requests on the same `XeroKiwi::Client` each get their own retry budget. Two
threads racing on a rate-limited tenant will each see independent
retry/backoff schedules — they won't coordinate.

If you need cross-thread coordination (e.g. "all threads should pause when
any one of them hits a 429"), build it at the application level using a
shared semaphore or rate limiter. Xero Kiwi doesn't ship one, because the right
shape depends entirely on your traffic patterns.

## Things the retry layer deliberately does NOT do

- **No retry on 500.** 500s are usually persistent. If you want them
  retried, add to `retry_statuses` explicitly.
- **No retry on 4xx (other than 429).** 4xx means the client did something
  wrong; retrying won't fix it. The exception is 429 (rate limit), which is
  classified as 4xx but is fundamentally a "wait and try again" signal.
- **No global rate limiter *by default*.** Xero Kiwi reacts to 429s as they
  happen but doesn't proactively throttle unless you opt in. For multi-worker
  setups where several processes hit the same tenant, wire up the
  Redis-backed token bucket described in
  [throttling.md](throttling.md) — it composes with this retry layer rather
  than replacing it.
- **No retry budget across calls.** Each `client.connections` (or any
  other call) gets a fresh `max` retries. There's no concept of "this client
  has had too many retries today and should stop trying."
- **No automatic Sidekiq integration.** When `RateLimitError` raises, it's
  up to your job to re-enqueue using the `retry_after` value. Xero Kiwi exposes
  it; what you do with it is your call.
