# OAuth

`XeroKiwi::OAuth` implements the Xero OAuth2 authorization-code flow. It's
**stateless** — every method is a pure function over its arguments — so the
same `OAuth` instance can serve both halves of the redirect (authorise →
callback) even when those halves run in different processes.

This doc walks through the full flow, the helper methods, PKCE, ID token
verification, and token revocation. For the long-term token lifecycle
(refresh, expiry, persistence callbacks), see [Tokens](tokens.md).

## The flow at a glance

1. **Build an authorise URL** with `oauth.authorization_url(...)` and
   redirect the user there.
2. The user signs in to Xero, picks tenants, grants permissions, and Xero
   redirects them to your `redirect_uri` with `?code=...&state=...`.
3. **Verify the `state`** with `XeroKiwi::OAuth.verify_state!` to defeat CSRF.
4. **Exchange the code** for a token with `oauth.exchange_code(...)`.
5. **(Optional) Verify the ID token** with `oauth.verify_id_token(...)` if
   you need to know who the user is.
6. **Use the access token** to call `client.connections` and the rest of
   the API.

## Constructing an OAuth instance

```ruby
oauth = XeroKiwi::OAuth.new(
  client_id:     ENV.fetch("XERO_CLIENT_ID"),
  client_secret: ENV.fetch("XERO_CLIENT_SECRET"),
  redirect_uri:  "https://app.example.com/xero/callback"
)
```

### Constructor options

| Option | Type | Required | Default | Purpose |
|--------|------|----------|---------|---------|
| `client_id:` | `String` | Yes | — | Your Xero app's client ID |
| `client_secret:` | `String` | Yes | — | Your Xero app's client secret |
| `redirect_uri:` | `String` | Conditional | `nil` | Required for `authorization_url` and `exchange_code`. **Optional** if you only use this instance for `revoke_token` or `verify_id_token`. |
| `adapter:` | Faraday adapter | No | `Faraday.default_adapter` | The HTTP adapter for token-endpoint and JWKS calls |

### Why `redirect_uri:` is optional

The OAuth instance is reused for several different operations. Some need
`redirect_uri`, some don't:

- **`authorization_url`**: Yes, always.
- **`exchange_code`**: Yes (Xero requires it in the form body for the exchange).
- **`revoke_token`**: No.
- **`verify_id_token`**: No.

If you're building a "revoke-only" instance for a logout flow, or a
"verify-only" instance for an external ID token, you don't need to invent a
fake redirect URL. Pass `redirect_uri: nil` (or just omit it). If you then
*do* call `authorization_url` or `exchange_code`, you'll get a clear
`ArgumentError` at call time rather than a confusing 400 from Xero.

## Step 1: building the authorisation URL

```ruby
state = XeroKiwi::OAuth.generate_state
pkce  = XeroKiwi::OAuth.generate_pkce

session[:xero_state]    = state
session[:xero_verifier] = pkce.verifier

redirect_to oauth.authorization_url(
  scopes: %w[openid profile email accounting.transactions offline_access],
  state:  state,
  pkce:   pkce
)
```

### `authorization_url` options

| Option | Type | Required | Purpose |
|--------|------|----------|---------|
| `scopes:` | `Array<String>` or `String` | Yes | The Xero scopes to request. Passed in space-separated to Xero. |
| `state:` | `String` | Yes | A random per-request value used for CSRF protection. Generate with `XeroKiwi::OAuth.generate_state` and stash in your session. |
| `pkce:` | `XeroKiwi::OAuth::PKCE` | No | A PKCE pair to bind the auth code to this request. See below. |
| `nonce:` | `String` | No | An optional OIDC nonce to embed in the ID token. Useful if you'll verify it on the callback. |

The returned URL is opaque — your job is just to redirect to it. Don't
parse it, don't reformat it.

### Common scope strings

Xero scopes are documented in their [scopes reference](https://developer.xero.com/documentation/guides/oauth2/scopes/).
Some commonly useful ones:

| Scope | What it grants |
|-------|----------------|
| `openid` | Required for OIDC (gets you an `id_token`) |
| `profile` | The user's display name |
| `email` | The user's email address |
| `offline_access` | **Required if you want a refresh token.** Without this, you only get an access token that dies in 30 minutes. |
| `accounting.transactions` | Read/write invoices, bills, payments, etc. |
| `accounting.contacts` | Read/write contacts |
| `accounting.settings` | Read accounting settings |

If you forget `offline_access`, you'll get a token but no `refresh_token`,
and `client.can_refresh?` will be false forever.

## State (CSRF protection)

The `state` parameter is the OAuth2 standard for defeating cross-site
request forgery. Without it, an attacker could trick a logged-in user into
linking their own Xero account to the attacker's app account.

### Generating and verifying

```ruby
# Before the redirect:
state = XeroKiwi::OAuth.generate_state
session[:xero_state] = state

# In your callback:
XeroKiwi::OAuth.verify_state!(
  received: params[:state],
  expected: session.delete(:xero_state)
)
# Raises XeroKiwi::OAuth::StateMismatchError on any mismatch.
```

### How the verification works

`verify_state!` does **constant-time** comparison via
`OpenSSL.fixed_length_secure_compare`, with a length check up front (the
OpenSSL function raises on unequal lengths, and the length itself isn't
secret).

It raises `XeroKiwi::OAuth::StateMismatchError` if:

- Either value is `nil`.
- The values have different byte lengths.
- The values have the same length but different content.

The error message is deliberately generic ("OAuth state parameter
mismatch") — don't reveal *what* the values were in user-facing output.

### State storage tips

- **Use the session** in a typical web app. Sessions are server-side or
  signed, so a user can't tamper with the stashed state.
- **Use `session.delete(...)`** in the callback to remove the stashed value
  in one go, preventing replay attacks where the same callback URL is hit
  twice.
- **Don't store state in a cookie** unless that cookie is signed. Otherwise
  the user can rewrite it.

## PKCE (Proof Key for Code Exchange)

PKCE binds the auth code to the original authorisation request: the client
generates a random verifier, sends a hash of it on the authorise call, then
proves possession of the original verifier when exchanging the code. An
attacker who intercepts the auth code can't redeem it without the verifier.

It's **required** for public clients (mobile apps, SPAs, anything where the
client secret isn't actually secret). For server-side confidential clients
it's **recommended** as defence in depth — there's no real downside.

### Generating a PKCE pair

```ruby
pkce = XeroKiwi::OAuth.generate_pkce
# or:
pkce = XeroKiwi::OAuth::PKCE.generate
```

A `XeroKiwi::OAuth::PKCE` exposes:

| Attribute | What it is |
|-----------|------------|
| `pkce.verifier` | A 43-character URL-safe random string. **Stash this in your session** — you'll need it on the callback. |
| `pkce.challenge` | The base64url-encoded SHA256 of the verifier (with no padding). This is what gets sent to Xero on the authorise call. |
| `pkce.to_h` | The form params Xero expects: `{ code_verifier:, code_challenge:, code_challenge_method: "S256" }`. Useful for testing or for building requests by hand. |

### Using PKCE in the flow

```ruby
# Authorise:
pkce = XeroKiwi::OAuth.generate_pkce
session[:xero_verifier] = pkce.verifier
redirect_to oauth.authorization_url(
  scopes: %w[...],
  state:  state,
  pkce:   pkce # passes code_challenge + code_challenge_method to Xero
)

# Callback:
token = oauth.exchange_code(
  code:          params[:code],
  code_verifier: session.delete(:xero_verifier) # prove we're the same client
)
```

If you pass a `pkce:` to `authorization_url` but **forget** the
`code_verifier:` on `exchange_code`, Xero will reject the exchange with
`invalid_grant` and XeroKiwi will raise `XeroKiwi::OAuth::CodeExchangeError`.

## Step 2: handling the callback

Xero redirects the user to your `redirect_uri` with one of two query string
shapes:

**On success:**
```
https://app.example.com/xero/callback?code=ABC123&state=stashed_state
```

**On failure** (user denied, scope rejected, etc):
```
https://app.example.com/xero/callback?error=access_denied&error_description=...
```

Always check for `error=` first:

```ruby
def callback
  if params[:error]
    redirect_to root_path, alert: params[:error_description]
    return
  end

  XeroKiwi::OAuth.verify_state!(
    received: params[:state],
    expected: session.delete(:xero_state)
  )

  # ... exchange the code
end
```

## Step 3: exchanging the code

```ruby
token = oauth.exchange_code(
  code:          params[:code],
  code_verifier: session.delete(:xero_verifier) # only if you used PKCE
)
```

### `exchange_code` options

| Option | Type | Required | Purpose |
|--------|------|----------|---------|
| `code:` | `String` | Yes | The auth code from the callback query string |
| `code_verifier:` | `String` | Conditional | Required if you sent a PKCE challenge in the authorise step |

### Return value

A `XeroKiwi::Token` containing the access token, refresh token, expires_at,
id_token, and scope. See [Tokens](tokens.md) for the full reference.

### Error behaviour

| Cause | Exception |
|-------|-----------|
| Code already used / expired (Xero codes are short-lived) | `XeroKiwi::OAuth::CodeExchangeError` |
| Wrong `redirect_uri` (must match the one used at authorise time) | `XeroKiwi::OAuth::CodeExchangeError` |
| PKCE verifier mismatch | `XeroKiwi::OAuth::CodeExchangeError` |
| Wrong client credentials | `XeroKiwi::OAuth::CodeExchangeError` |
| Network error | bubbles up as a `Faraday::ConnectionFailed` |

`XeroKiwi::OAuth::CodeExchangeError` inherits from `XeroKiwi::AuthenticationError`,
so you can catch the broader class if you don't care about the distinction.

## ID token verification

If you requested the `openid` scope, Xero returns an `id_token` (a JWT) in
the token response. The ID token contains claims about who the user is —
their `sub`, `email`, `given_name`, etc. **You should verify it before
trusting any of those claims**, otherwise an attacker who steals an access
token could feed you a forged ID token to impersonate someone.

### Verifying via the OAuth instance (recommended)

```ruby
verified = oauth.verify_id_token(token.id_token)

verified.subject     # the OIDC `sub` — Xero's user identifier
verified.email       # if `email` scope was granted
verified.given_name  # if `profile` scope was granted
verified.family_name
verified.expires_at  # Time
verified.issued_at   # Time
verified.claims      # full claims hash
```

This route uses the OAuth instance's **JWKS cache**: the first verification
fetches Xero's signing keys from
`https://identity.xero.com/.well-known/openid-configuration/jwks` and the
result is cached in memory for an hour. Subsequent verifications on the
same instance reuse the cached keys, so verifying 100 tokens in a session
costs you exactly one HTTPS round-trip.

### Verifying standalone

If you don't have an `OAuth` instance handy:

```ruby
verified = XeroKiwi::OAuth::IDToken.verify(
  id_token,
  client_id: "your_client_id"
)
```

The standalone class method **fetches JWKS fresh on every call** via
`Net::HTTP`. Fine for one-off use, wasteful in a hot loop. If you find
yourself calling it repeatedly, switch to the OAuth instance method.

You can also inject your own JWKS provider:

```ruby
XeroKiwi::OAuth::IDToken.verify(
  id_token,
  client_id: "...",
  jwks: -> { my_cached_jwks_hash }
)
```

The `jwks:` proc must return an array of JWK hashes (the contents of the
`"keys"` array in a standard JWKS document).

### What gets verified

| Check | How |
|-------|-----|
| Signature | RS256, against the public key whose `kid` matches the JWT header. Other algorithms are rejected. |
| Issuer (`iss`) | Must equal `https://identity.xero.com`. |
| Audience (`aud`) | Must equal the `client_id` you passed in. |
| Expiry (`exp`) | Must be in the future (with no clock skew tolerance). |
| Nonce (`nonce`) | Only if you pass `nonce:` to `verify`. Constant-time compare. |

Anything that fails raises `XeroKiwi::OAuth::IDTokenError` with a descriptive
message ("ID token verification failed: ...").

### Nonce verification

If you sent a nonce in the authorise call, you should verify it on the way
back:

```ruby
# Authorise:
nonce = SecureRandom.urlsafe_base64(16)
session[:xero_nonce] = nonce
redirect_to oauth.authorization_url(scopes: ..., state: ..., nonce: nonce)

# Callback:
verified = oauth.verify_id_token(
  token.id_token,
  nonce: session.delete(:xero_nonce)
)
```

The nonce check fails if the token doesn't contain a `nonce` claim, if the
claim doesn't match what you sent, or if the comparison would have raised.

## Token revocation

Use this for "disconnect Xero from my app" / logout flows.

### Via the Client (most common)

```ruby
client.revoke_token!
credential.destroy!
```

See [Tokens — revoking tokens](tokens.md#revoking-tokens) for the full
story.

### Via OAuth directly

If you have a refresh token in hand:

```ruby
oauth = XeroKiwi::OAuth.new(
  client_id:     ENV.fetch("XERO_CLIENT_ID"),
  client_secret: ENV.fetch("XERO_CLIENT_SECRET")
  # no redirect_uri needed
)

oauth.revoke_token(refresh_token: "1//...")
```

Returns `true` on success, raises `XeroKiwi::AuthenticationError`/`XeroKiwi::ClientError`
on failure.

### Why we always revoke the refresh token

Per RFC 7009 you can pass either an access token or a refresh token to the
revoke endpoint. **But** revoking the access token only kills that one
access token — the refresh token is still alive and can mint a new one
immediately. Revoking the refresh token invalidates the entire chain.

`XeroKiwi::OAuth#revoke_token` only accepts a refresh token (the keyword arg
is `refresh_token:`) precisely to prevent the foot-gun of "I called revoke
but the user is still logged in."

## Full Rails-style example

```ruby
class XeroOAuthController < ApplicationController
  def authorize
    state = XeroKiwi::OAuth.generate_state
    pkce  = XeroKiwi::OAuth.generate_pkce

    session[:xero_state]    = state
    session[:xero_verifier] = pkce.verifier

    redirect_to oauth.authorization_url(
      scopes: %w[openid profile email accounting.transactions offline_access],
      state:  state,
      pkce:   pkce
    )
  end

  def callback
    if params[:error]
      redirect_to root_path, alert: params[:error_description]
      return
    end

    XeroKiwi::OAuth.verify_state!(
      received: params[:state],
      expected: session.delete(:xero_state)
    )

    token = oauth.exchange_code(
      code:          params[:code],
      code_verifier: session.delete(:xero_verifier)
    )

    # Confirm who the user is before storing anything
    identity = oauth.verify_id_token(token.id_token)

    # Discover tenants
    api_client = XeroKiwi::Client.new(access_token: token.access_token)
    tenants = api_client.connections

    # Persist the credential
    XeroCredential.create!(
      user_email:    identity.email,
      access_token:  token.access_token,
      refresh_token: token.refresh_token,
      expires_at:    token.expires_at,
      tenants:       tenants.map { |t| { id: t.tenant_id, name: t.tenant_name } }
    )

    redirect_to dashboard_path
  rescue XeroKiwi::OAuth::StateMismatchError
    redirect_to root_path, alert: "Authentication failed (CSRF check)"
  rescue XeroKiwi::OAuth::CodeExchangeError
    redirect_to root_path, alert: "Could not complete Xero authorisation"
  rescue XeroKiwi::OAuth::IDTokenError
    redirect_to root_path, alert: "Could not verify Xero identity token"
  end

  def disconnect
    credential = current_user.xero_credential

    client = XeroKiwi::Client.new(
      access_token:  credential.access_token,
      refresh_token: credential.refresh_token,
      expires_at:    credential.expires_at,
      client_id:     ENV.fetch("XERO_CLIENT_ID"),
      client_secret: ENV.fetch("XERO_CLIENT_SECRET")
    )

    client.revoke_token!
    credential.destroy!
    redirect_to root_path, notice: "Disconnected from Xero"
  end

  private

  def oauth
    @oauth ||= XeroKiwi::OAuth.new(
      client_id:     Rails.application.credentials.xero[:client_id],
      client_secret: Rails.application.credentials.xero[:client_secret],
      redirect_uri:  xero_oauth_callback_url
    )
  end
end
```

## Things OAuth deliberately does NOT do

- **No session storage.** XeroKiwi gives you `generate_state` and
  `generate_pkce` as helpers but never touches your session/cookies/Redis.
  Where you stash the values is your problem — and that's a feature,
  because every framework is different.
- **No automatic state tracking on the OAuth instance.** Some gems offer a
  stateful "session" object that holds the state and verifier in memory
  between authorise and callback. That only works if both halves of the
  flow run in the same process, which isn't true for any web app where the
  redirect lands on a different request. Stateless functions compose
  better.
- **No `at_hash` verification on ID tokens.** OIDC defines an optional
  `at_hash` claim that lets you verify the access token hasn't been
  tampered with in transit. It's rarely used and adds complexity. Skip
  until requested.
- **No nonce generation helper.** `SecureRandom.urlsafe_base64(16)` at
  the call site is already simple — could add `OAuth.generate_nonce` for
  symmetry with `generate_state`, but it'd be one line of code.
