# Tokens

This doc covers everything about token *state* in Xero Kiwi: the `XeroKiwi::Token`
value object, how the client refreshes tokens automatically, the persistence
callback, manual refresh, revocation, and the gotchas around token rotation.

For the OAuth *protocol* (building authorise URLs, exchanging codes), see
[OAuth](oauth.md).

## The `XeroKiwi::Token` value object

A `XeroKiwi::Token` is an immutable bundle of OAuth state — the access/refresh
pair plus all the metadata Xero returns at refresh time:

```ruby
token = XeroKiwi::Token.new(
  access_token:  "ya29...",
  refresh_token: "1//...",
  expires_at:    Time.now + 1800,
  token_type:    "Bearer",
  id_token:      "eyJhbG...",
  scope:         "openid offline_access accounting.transactions"
)
```

You usually don't construct one by hand — it's what `OAuth#exchange_code` and
`OAuth#refresh_token` (via `TokenRefresher`) return, and what
`XeroKiwi::Client#token` exposes.

### Constructor options

| Option | Type | Default | Required |
|--------|------|---------|----------|
| `access_token:` | `String` | — | Yes |
| `refresh_token:` | `String` | `nil` | No |
| `expires_at:` | `Time` | `nil` | No |
| `token_type:` | `String` | `"Bearer"` | No |
| `id_token:` | `String` | `nil` | No |
| `scope:` | `String` | `nil` | No |

### Building from a Xero OAuth response

`Token.from_oauth_response` converts a Xero token-endpoint payload (which
returns `expires_in` as seconds-from-now) into a Token with an absolute
`expires_at`:

```ruby
payload = {
  "access_token"  => "...",
  "refresh_token" => "...",
  "expires_in"    => 1800,
  "token_type"    => "Bearer",
  "scope"         => "openid offline_access ...",
  "id_token"      => "..."
}

token = XeroKiwi::Token.from_oauth_response(payload)
# expires_at is computed as Time.now + 1800

# You can also pin the anchor time, which is useful for tests:
token = XeroKiwi::Token.from_oauth_response(payload, requested_at: some_time)
```

This method accepts both string-keyed and symbol-keyed payloads.

## Expiry helpers

| Method | What it returns |
|--------|-----------------|
| `token.expired?(now: Time.now)` | `true` if `expires_at` is in the past. **Returns `false` when `expires_at` is nil** — without an expiry we have no signal to act on. |
| `token.expiring_soon?(within: 60, now: Time.now)` | `true` if `expires_at` falls within `within` seconds of `now`. The default 60s window is what `XeroKiwi::Client` uses for its proactive refresh. |
| `token.valid?(now: Time.now)` | `true` if the access token is non-empty AND not expired. |
| `token.refreshable?` | `true` if a non-empty refresh token is present. |

The `now:` keyword arg lets you inject a fixed time for testing.

### Why `expired?` returns false on nil `expires_at`

If you don't know when the token expires (e.g. you loaded a credential from
storage that was created before you tracked expiry), Xero Kiwi treats it as
"unknown" and assumes valid. The fallback is reactive — your first 401 will
trigger a refresh.

Set `expires_at:` whenever you can; it's strictly better than relying on
reactive refresh, which costs you a wasted API call before the refresh fires.

## Refreshing the token

There are two ways the client refreshes tokens for you:

### Automatic (preferred)

If you constructed the client with refresh credentials, every API call goes
through these checks:

1. **Proactive** — before the request fires, if `token.expiring_soon?`
   returns true, the client refreshes first.
2. **Reactive** — if the request returns 401 anyway, the client refreshes
   and retries the request once.

You don't have to do anything to opt in — it's the default behaviour. Just
make sure to provide all the refresh ingredients at construction time:

```ruby
client = XeroKiwi::Client.new(
  access_token:     credential.access_token,
  refresh_token:    credential.refresh_token,
  expires_at:       credential.expires_at,
  client_id:        ENV.fetch("XERO_CLIENT_ID"),
  client_secret:    ENV.fetch("XERO_CLIENT_SECRET"),
  on_token_refresh: ->(token) { credential.update!(token.to_h) }
)
```

### Manual

If you need to force a refresh outside of an API call:

```ruby
new_token = client.refresh_token!
# or just:
client.refresh_token!
client.token # the new token
```

`refresh_token!` raises `XeroKiwi::TokenRefreshError` if:

- The client has no refresh credentials (`client_id`/`client_secret` missing).
- The current token has no `refresh_token`.
- Xero rejects the refresh (e.g. `invalid_grant` because the refresh token
  was already rotated by another process — see
  [the rotation gotcha](#refresh-token-rotation) below).

### `client.can_refresh?`

True if and only if all the ingredients are in place: client credentials *and*
a non-empty refresh token. Use this to check before calling `refresh_token!`
explicitly:

```ruby
if client.can_refresh?
  client.refresh_token!
else
  # surface a "needs re-auth" state
end
```

## The `on_token_refresh` callback

This is the most important integration point in the gem. Every time the
client refreshes the token — proactively, reactively, or via a manual
`refresh_token!` — it calls your callback with the new `XeroKiwi::Token`:

```ruby
on_token_refresh: ->(token) { credential.update!(token.to_h) }
```

The callback fires from inside the refresh mutex, so by the time it runs,
the new token is the canonical in-memory state. If you don't persist it,
the next process to load the credential will use the now-invalid old refresh
token and fail.

### Persistence patterns

Different applications store credentials differently. The callback works the
same in all of them — Xero Kiwi just hands you the new token and trusts you to
put it somewhere:

```ruby
# Rails / ActiveRecord
on_token_refresh: ->(token) { credential.update!(access_token: token.access_token, refresh_token: token.refresh_token, expires_at: token.expires_at) }

# Sequel
on_token_refresh: ->(token) { DB[:credentials].where(id: id).update(token.to_h) }

# Local CLI tool with a JSON file
on_token_refresh: ->(token) { File.write("~/.xero", JSON.dump(token.to_h)) }

# Background sync architecture: write through a queue so persistence
# happens in a single-writer worker (avoids the rotation race below)
on_token_refresh: ->(token) { TokenWriter.enqueue(tenant_id, token.to_h) }
```

The callback receives a `XeroKiwi::Token`, so you can call `.to_h` to get a
plain hash, or pick fields off it directly.

## Refresh token rotation

**Xero rotates refresh tokens on every use.** When you successfully refresh,
Xero returns a *new* refresh token alongside the new access token, and the
old refresh token is immediately invalidated. There is no way to recover it.

This is the source of the most common production bug with OAuth-based
integrations:

> **Two workers race.** Worker A and Worker B both load the same credential
> row from the database, both notice the token is expiring, and both try to
> refresh. Worker A wins, gets a new refresh token, persists it. Worker B
> tries to use the old refresh token (which it loaded before A persisted)
> and gets `invalid_grant`. From Worker B's perspective, the credential
> looks dead — but it's not, A just rotated it.

Xero Kiwi mitigates this in two ways:

1. **Single-process safety.** A `Mutex` around refresh, with a double-check
   inside, prevents multiple threads in the *same process* from racing.
2. **Single-process safety only.** The mutex doesn't help across processes.

### Multi-process refresh

If you have multiple processes sharing one credential (e.g. Sidekiq workers,
multiple Rails servers behind a load balancer), the in-process mutex doesn't
protect you. Options:

#### Option A — Single-writer architecture

Funnel all refreshes through one process. When a worker notices a token is
expiring, it enqueues a "please refresh this credential" job to a single
worker that handles refresh exclusively. The worker that requested the
refresh waits for the result (or just retries with the freshly-loaded
credential).

This is the cleanest approach but requires architecture work.

#### Option B — Catch the race and reload

When `XeroKiwi::TokenRefreshError` fires, the most common cause is "another
process already refreshed." Reload the credential from the database — if
the refresh token has changed, use the new one and retry. If it's the
same, the credential is genuinely dead and you need to re-authorise.

```ruby
def with_xero_client
  credential = XeroCredential.find(id)
  client = build_client(credential)

  yield client

rescue XeroKiwi::TokenRefreshError
  credential.reload
  if credential.refresh_token != client.token.refresh_token
    retry # another process refreshed; pick up their new token
  else
    credential.update!(needs_reauth: true)
    raise
  end
end
```

#### Option C — Distributed lock

Use Redis (or Postgres advisory locks, etc.) to take a distributed lock
keyed by credential ID before refreshing. Slower but more robust than
Option B.

Xero Kiwi doesn't ship any of these — they're application-level decisions that
depend on your infrastructure. But the existence of `client.token.refreshable?`
and the explicit `XeroKiwi::TokenRefreshError` give you the building blocks.

## Revoking tokens

Revocation tells Xero "please invalidate this token." Use it for "disconnect
Xero from my app" / logout flows.

### Via `XeroKiwi::Client`

```ruby
client.revoke_token!
credential.destroy! # caller's job
```

This:

1. POSTs to `https://identity.xero.com/connect/revocation` with the client's
   current refresh token.
2. Returns `true` on success.
3. Raises `XeroKiwi::TokenRefreshError` if the client has no refresh capability,
   or `XeroKiwi::AuthenticationError` if Xero rejects the revoke.

After revocation, **treat the client as dead.** Subsequent API calls will
401, and reactive refresh will fail because the refresh token is gone too.
Xero Kiwi doesn't set an internal flag on the client — there's no
`client.revoked?` predicate — because the right thing for a caller to do
post-revocation is throw the client away, not keep using it.

### Via `XeroKiwi::OAuth` directly

If you have a refresh token in hand and don't want to construct a Client:

```ruby
oauth = XeroKiwi::OAuth.new(
  client_id:     ENV.fetch("XERO_CLIENT_ID"),
  client_secret: ENV.fetch("XERO_CLIENT_SECRET")
  # no redirect_uri needed for revoke-only
)

oauth.revoke_token(refresh_token: stored_refresh_token)
```

`OAuth#revoke_token` is the protocol-level method; `Client#revoke_token!`
is a thin convenience over it.

### Why we always pass the refresh token, not the access token

Per RFC 7009 you can revoke either the access token or the refresh token.
Xero accepts both. **But** revoking the access token only kills that one
access token — the refresh token stays alive and can mint a new one
immediately. Revoking the refresh token invalidates the entire chain.

Xero Kiwi enforces the refresh-token path: `Client#revoke_token!` raises if you
don't have a refresh token, rather than silently revoking the access token
(which would do almost nothing useful). This avoids a foot-gun where users
think they've logged out but the token is still happily working.

## Inspecting tokens

`XeroKiwi::Token#inspect` redacts the access token so it doesn't accidentally
end up in logs:

```ruby
token.inspect
# => "#<XeroKiwi::Token access_token=[FILTERED] refreshable=true expires_at=2026-04-09 14:30:00 UTC>"
```

`token.to_h` does NOT redact — it returns the full hash for storage. Don't
log the full hash.

## Things tokens deliberately do NOT do

- **No automatic expiry from `Time.now`.** Tokens are immutable; their
  expiry is fixed at construction. The "expiring" predicates are
  computations against a `now:` parameter, not stateful checks.
- **No comparison of access token bytes.** `XeroKiwi::Token#==` compares the
  full hash, which works for "is this the same token?" but isn't a security
  check. Don't use it for authentication.
- **No JWT decoding of the access token.** Xero's access tokens are JWTs,
  but Xero Kiwi doesn't peek at their contents. The `id_token` is the OIDC
  identity assertion you should care about; see [OAuth](oauth.md#id-token-verification)
  for verifying it.
