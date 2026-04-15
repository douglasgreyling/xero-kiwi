# Errors

Every failure path in XeroKiwi raises a typed exception. This page walks through
the hierarchy, explains what each class means, and tells you what to catch
in common situations.

## The hierarchy

```
StandardError
└─ XeroKiwi::Error                       (root — catch this for "anything XeroKiwi raised")
   ├─ XeroKiwi::APIError                 (root for HTTP responses; carries status + body)
   │  ├─ XeroKiwi::AuthenticationError   (401)
   │  │  ├─ XeroKiwi::TokenRefreshError  (refresh round-trip failed)
   │  │  └─ XeroKiwi::OAuth::CodeExchangeError  (auth-code exchange failed)
   │  ├─ XeroKiwi::ClientError           (other 4xx)
   │  ├─ XeroKiwi::ServerError           (5xx)
   │  └─ XeroKiwi::RateLimitError        (429, with retry_after + problem)
   ├─ XeroKiwi::OAuth::StateMismatchError  (CSRF check failed)
   └─ XeroKiwi::OAuth::IDTokenError        (ID token JWT verification failed)
```

A few things worth noticing about the shape:

- **Everything XeroKiwi raises** descends from `XeroKiwi::Error`. If you only want
  one rescue clause for "the Xero integration broke," catch this.
- **HTTP responses** descend from `XeroKiwi::APIError`, which carries `status`
  and `body` attributes you can inspect.
- **OAuth-specific errors** for state mismatch and ID token verification
  descend from `XeroKiwi::Error` directly (not `APIError`) because they don't
  come from an HTTP response — they're local validation failures.
- **`XeroKiwi::TokenRefreshError`** and **`XeroKiwi::OAuth::CodeExchangeError`** are
  both `AuthenticationError` subclasses, because the practical recovery is
  the same as for any 401: the user needs to re-authorise.

## Class reference

### `XeroKiwi::Error`

The root class. Inherits from `StandardError`. You almost never raise this
directly — it exists as a catch-all for code that wants to rescue "any XeroKiwi
problem" without enumerating every subclass.

### `XeroKiwi::APIError`

The base class for HTTP errors. Constructor: `APIError.new(status, body, message = nil)`.

Attributes:

| Attribute | Type | What it is |
|-----------|------|------------|
| `error.status` | `Integer` | The HTTP status code (e.g. 401, 429, 500). |
| `error.body` | parsed body | The response body, parsed as JSON when the response was JSON, otherwise the raw string. |
| `error.message` | `String` | A descriptive message. Defaults to `"Xero API responded with #{status}: #{body.inspect}"`. |

### `XeroKiwi::AuthenticationError` (HTTP 401)

The access token was rejected. The most common causes:

- Token has expired and there's no refresh capability.
- Token was revoked.
- Token has the wrong scopes for this endpoint.
- The wrong tenant ID was passed in the `Xero-Tenant-Id` header.

If your client has refresh capability, XeroKiwi will already have tried to
refresh and retry exactly once before this raises. Seeing `AuthenticationError`
on a refresh-capable client means **the second 401 also failed** — refresh
won't fix it, and you need to either re-authorise or surface the error.

### `XeroKiwi::TokenRefreshError`

A subclass of `AuthenticationError`. Raised when the refresh round-trip
itself fails. Most common cause: **the refresh token has been rotated by
another process** (see [the rotation gotcha in the tokens
doc](tokens.md#refresh-token-rotation)).

This is different from "the user must re-auth" in subtle ways:

- **Refresh token rotated**: another process refreshed before you did.
  Reload the credential from storage and retry.
- **Refresh token genuinely expired** (60 days unused): the user must
  re-authorise.

You can't tell these apart from the exception alone — both look like
`invalid_grant` from Xero. The recovery pattern in
[Tokens — multi-process refresh](tokens.md#multi-process-refresh) handles
both cases.

### `XeroKiwi::OAuth::CodeExchangeError`

Also a subclass of `AuthenticationError`. Raised when `oauth.exchange_code`
fails:

- The auth code expired (Xero's codes are very short-lived).
- The code was already used (codes are single-use).
- The `redirect_uri` doesn't match what was used at authorise time.
- The PKCE verifier doesn't match the challenge sent at authorise time.
- The client credentials are wrong.

The user needs to restart the OAuth flow from the authorise step.

### `XeroKiwi::ClientError` (other HTTP 4xx)

A 4xx response that isn't 401 or 429. Most commonly:

| Status | Meaning |
|--------|---------|
| 400 | Bad request — usually a malformed body or query param |
| 403 | The token is valid but doesn't have the right scope/permission |
| 404 | The resource doesn't exist (or was already deleted) |
| 422 | Validation error — Xero rejected the payload |

The body will usually contain a Xero-specific error structure with details.
Inspect `error.body` to surface it.

### `XeroKiwi::ServerError` (HTTP 5xx)

A 5xx response that wasn't retried. XeroKiwi retries 502/503/504 automatically
(see [retries and rate limits](retries-and-rate-limits.md)) so by the time
you see this, the retries are exhausted or the status was 500 (which XeroKiwi
deliberately doesn't retry, since 500s are usually persistent bugs in the
request rather than transient infrastructure issues).

### `XeroKiwi::RateLimitError` (HTTP 429)

A subclass of `APIError`. Raised when retries on a 429 are exhausted.

Extra attributes beyond `APIError`:

| Attribute | Type | What it is |
|-----------|------|------------|
| `error.retry_after` | `Float` or `nil` | The value of the `Retry-After` header in seconds, if Xero sent one. |
| `error.problem` | `String` or `nil` | The value of the `X-Rate-Limit-Problem` header — typically `"minute"`, `"day"`, or `"appminute"`. Tells you which limit you hit. |

`retry_after` lets your application decide how to back off — for example, a
Sidekiq job can re-enqueue itself with that delay rather than hammering
Xero.

### `XeroKiwi::OAuth::StateMismatchError`

Raised by `XeroKiwi::OAuth.verify_state!` when the `state` parameter Xero
echoed back doesn't match what you stashed before redirecting. **This
indicates a forged callback or a session that was lost between request and
response.** Treat it as a security event — log it and refuse to proceed.

This is *not* a Xero error; it's a local CSRF check that fires before any
HTTP call.

### `XeroKiwi::OAuth::IDTokenError`

Raised by `XeroKiwi::OAuth::IDToken.verify` (or `oauth.verify_id_token`) when
the ID token JWT can't be verified. Causes:

- Bad signature.
- Wrong issuer.
- Wrong audience.
- Token expired.
- Nonce mismatch (when nonce verification was requested).
- Network failure fetching JWKS.

The error message has a brief description of which check failed (e.g.
`"ID token verification failed: Signature verification failed"`,
`"ID token nonce mismatch"`).

## What to catch when

### "Any XeroKiwi failure"

```ruby
begin
  client.connections
rescue XeroKiwi::Error => e
  Rails.logger.error("Xero call failed: #{e.message}")
end
```

### "Authentication broke; user needs to re-auth"

```ruby
begin
  client.connections
rescue XeroKiwi::AuthenticationError
  redirect_to xero_reauth_path
end
```

This catches `TokenRefreshError` and `CodeExchangeError` too, since they're
both `AuthenticationError` subclasses. That's usually what you want — they
all imply "the credentials are dead, restart the flow."

### "Rate limited — back off"

```ruby
begin
  client.connections
rescue XeroKiwi::RateLimitError => e
  RetryWorker.perform_in(e.retry_after.seconds, args)
end
```

### "Anything Xero said no to"

```ruby
begin
  client.connections
rescue XeroKiwi::APIError => e
  Rails.logger.warn("Xero #{e.status}: #{e.body}")
  raise
end
```

### "OAuth callback failed for any reason"

```ruby
def callback
  XeroKiwi::OAuth.verify_state!(received: params[:state], expected: session.delete(:xero_state))
  token = oauth.exchange_code(code: params[:code], code_verifier: session.delete(:xero_verifier))
  oauth.verify_id_token(token.id_token)
  # ...
rescue XeroKiwi::OAuth::StateMismatchError
  redirect_to root_path, alert: "Authentication failed (CSRF check)"
rescue XeroKiwi::OAuth::CodeExchangeError
  redirect_to root_path, alert: "Could not complete Xero authorisation"
rescue XeroKiwi::OAuth::IDTokenError
  redirect_to root_path, alert: "Could not verify Xero identity"
end
```

Three separate rescue clauses give you three different user-facing
messages, which is usually what you want for an OAuth callback — different
failures imply different user actions.

### Distinguishing TokenRefreshError from generic 401

If you want to handle the rotation race specifically:

```ruby
begin
  client.connections
rescue XeroKiwi::TokenRefreshError
  credential.reload
  if credential.refresh_token != original_refresh_token
    retry # another process refreshed; pick up their token
  else
    credential.update!(needs_reauth: true)
    raise
  end
rescue XeroKiwi::AuthenticationError
  # 401 that wasn't a refresh failure (e.g. token revoked at Xero's end)
  credential.update!(needs_reauth: true)
end
```

Order matters — `TokenRefreshError` is more specific than
`AuthenticationError`, so it must come first.

## Things the error system deliberately does NOT do

- **No "this error is retryable" predicate.** XeroKiwi already retries the
  cases that *should* be retried at the HTTP level. By the time an exception
  reaches your code, the retries are exhausted and the situation is
  application-level. Adding `error.retryable?` would create a tempting
  foot-gun where callers retry inside their own code, doubling up on the
  retries XeroKiwi is already doing.
- **No automatic Sentry / Bugsnag integration.** Errors raise normally;
  configure your own observability layer to catch them at the boundary.
- **No `error.code` enum.** The HTTP `status` is the enum. Inspecting it
  in user code is usually fine (`error.status == 404`).
- **No localised error messages.** Messages are English and developer-facing.
  Translate them to user-facing language at your application's surface,
  not in the gem.
