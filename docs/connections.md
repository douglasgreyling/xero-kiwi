# Connections

In Xero's terminology, a **connection** is one tenant (organisation or
practice) that an access token has been authorised against. A single user can
authorise your app against multiple tenants in one OAuth flow, and each one
becomes a separate connection.

This is the first thing you'll typically call after exchanging an OAuth code
for tokens — you need the `tenant_id` from a connection before you can hit
any of the actual accounting endpoints.

> See: [Xero docs — managing connections](https://developer.xero.com/documentation/best-practices/managing-connections/connections)

## Listing connections

```ruby
client = XeroKiwi::Client.new(access_token: "ya29...")

client.connections.each do |connection|
  puts "#{connection.tenant_name} — #{connection.tenant_id}"
end
```

`client.connections` returns an `Array<XeroKiwi::Connection>`. The array is empty
if the user authorised your app but didn't pick any tenants (rare, but
possible). The endpoint doesn't take any filtering parameters — Xero returns
everything the token has access to.

## The Connection object

Each `XeroKiwi::Connection` is an immutable value object exposing the fields Xero
returns:

| Attribute | Type | What it is |
|-----------|------|------------|
| `id` | `String` | The **connection** UUID. This is what you pass to `delete_connection` to disconnect. |
| `tenant_id` | `String` | The **tenant** UUID. This is what you put in the `Xero-Tenant-Id` header on every accounting API call. |
| `tenant_type` | `String` | Either `"ORGANISATION"` or `"PRACTICE"`. |
| `tenant_name` | `String` | The display name (e.g. "Maple Florists Ltd"). |
| `auth_event_id` | `String` | The OAuth event UUID. Useful for correlating with Xero's audit logs. |
| `created_date_utc` | `Time` | When the connection was first established, parsed as UTC. |
| `updated_date_utc` | `Time` | When the connection was last updated, parsed as UTC. |

### `id` vs `tenant_id` — important

These are **different UUIDs**. Get them mixed up and your API calls will
mysteriously 401.

- `connection.id` is the unique identifier of the *connection record itself*,
  used for deletion.
- `connection.tenant_id` is the unique identifier of the *tenant* (the Xero
  organisation), used in the `Xero-Tenant-Id` header on every accounting
  request.

## Predicates

```ruby
connection.organisation? # tenant_type == "ORGANISATION"
connection.practice?     # tenant_type == "PRACTICE"
```

## Equality and hashing

Two connections are `==` if they have the same `id`, even if other attributes
differ. This is convenient for set operations:

```ruby
old_connections - new_connections # diff by id
```

`#hash` is consistent with `==`, so connections work as hash keys.

## Date parsing

Xero serialises dates in C# DateTime format and frequently omits the timezone
marker on values that are documented as UTC (e.g. `"2019-07-09T23:40:30.1833130"`).
Xero Kiwi force-appends a `Z` before parsing so you always get a UTC `Time` back —
without this, `Time.parse` would silently fall back to local time and you'd
get the wrong instant.

If you want the raw string Xero sent, the connection's `to_h` only exposes
the parsed `Time` objects. Reach into the response yourself if you need the
original strings.

## Disconnecting a tenant

```ruby
# By id
client.delete_connection("e1eede29-f875-4a5d-8470-17f6a29a88b1")

# Or by passing the Connection object — its `id` is used
connection = client.connections.first
client.delete_connection(connection)
```

`delete_connection` returns `true` on success and raises on failure. Both
forms hit `DELETE /connections/:id`.

After a successful delete:

- The named tenant is detached from the access token.
- **Other tenants** authorised by the same token are *not* affected — only
  this one connection is gone.
- Calls that include the deleted `tenant_id` in their `Xero-Tenant-Id` header
  will start failing with 401.

### Error behaviour

| HTTP status | Exception | What it usually means |
|-------------|-----------|------------------------|
| 204 No Content | (none — returns `true`) | Success |
| 401 | `XeroKiwi::AuthenticationError` | Access token is invalid or expired |
| 403 | `XeroKiwi::ClientError` | The token doesn't have permission to disconnect this tenant |
| 404 | `XeroKiwi::ClientError` | The connection ID doesn't exist (or was already deleted) |

A 404 is usually idempotent-friendly — if you're trying to make sure a tenant
is disconnected, catching `XeroKiwi::ClientError` and ignoring 404s is reasonable:

```ruby
begin
  client.delete_connection(id)
rescue XeroKiwi::ClientError => e
  raise unless e.status == 404
end
```

## Common patterns

### Find a tenant by name

```ruby
target = client.connections.find { |c| c.tenant_name == "Maple Florists Ltd" }
target&.tenant_id # use this in subsequent API calls
```

### Disconnect everything

For "remove Xero from my app" flows where the user wants a full disconnect,
combine deletion with token revocation:

```ruby
client.connections.each { |c| client.delete_connection(c) }
client.revoke_token!
credential.destroy!
```

The order matters — once you `revoke_token!`, the access token is dead and
subsequent `delete_connection` calls will 401. So delete first, then revoke.

(In practice you can skip the per-connection deletes entirely if you're going
to revoke the token anyway — revoking the refresh token invalidates the
access token, which detaches all connections at once. The per-connection
delete is for when you want to disconnect *some* tenants and keep others.)

### Iterating without holding the array

Connections are usually a small list (1-10 entries) so loading them all is
cheap. But if you only need one:

```ruby
client.connections.lazy.find { |c| c.tenant_id == target_tenant_id }
```

The lazy enumerator doesn't help here — `client.connections` already does
the full HTTP fetch — but it's idiomatic and avoids materialising more than
you need into local variables.
