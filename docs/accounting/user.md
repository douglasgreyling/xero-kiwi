# Users

Xero **users** are the people who have access to a Xero organisation. The Users
endpoint is read-only — you can list and fetch users, but not create or modify
them through the API. You need a `tenant_id` from a
[connection](../connections.md) before you can fetch users.

> See: [Xero docs — Users](https://developer.xero.com/documentation/api/accounting/users)

## Listing users

```ruby
client = XeroKiwi::Client.new(access_token: "ya29...")

# Pass a tenant ID string…
users = client.users("70784a63-d24b-46a9-a4db-0e70a274b056")

# …or a XeroKiwi::Connection (its tenant_id is used automatically).
connection = client.connections.first
users = client.users(connection)
```

`client.users` hits `GET /api.xro/2.0/Users` with the `Xero-Tenant-Id` header
set to the tenant you specify. It returns an `Array<XeroKiwi::Accounting::User>`.

## Fetching a single user

```ruby
user = client.user(tenant_id, "7cf47fe2-c3dd-4c6b-9895-7ba767ba529c")
user.email_address  # => "john.smith@mail.com"
```

`client.user` hits `GET /api.xro/2.0/Users/{UserID}` and returns a single
`XeroKiwi::Accounting::User`, or `nil` if the response is empty.

## The User object

Each `XeroKiwi::Accounting::User` is an immutable value object exposing the fields
Xero returns:

| Attribute | Type | What it is |
|-----------|------|------------|
| `user_id` | `String` | The unique Xero identifier for the user. |
| `email_address` | `String` | The user's email address. |
| `first_name` | `String` | The user's first name. |
| `last_name` | `String` | The user's last name. |
| `updated_date_utc` | `Time` | When the user was last modified, parsed as UTC. |
| `is_subscriber` | `Boolean` | Whether the user is the subscriber (billing owner). |
| `organisation_role` | `String` | The user's role — see [Organisation roles](#organisation-roles) below. |

## Predicates

```ruby
user.subscriber?  # is_subscriber == true
```

## Organisation roles

| Role | Description |
|------|-------------|
| `READONLY` | Read-only access |
| `INVOICEONLY` | Invoice-only access |
| `STANDARD` | Standard user |
| `FINANCIALADVISER` | Financial adviser role |
| `MANAGEDCLIENT` | Managed client (Partner Edition only) |
| `CASHBOOKCLIENT` | Cashbook client (Partner Edition only) |
| `ADMIN` | Full admin access |

## Equality and hashing

Two users are `==` if they share the same `user_id`. `#hash` is consistent with
`==`, so users work as hash keys and in sets.

## Date parsing

The `updated_date_utc` field uses Xero's .NET JSON timestamp format
(`/Date(1516230549137+0000)/`). XeroKiwi parses both .NET JSON and ISO 8601
formats transparently — the attribute is always a UTC `Time` object.

## Error behaviour

| HTTP status | Exception | What it usually means |
|-------------|-----------|------------------------|
| 200 | (none — returns users) | Success |
| 401 | `XeroKiwi::AuthenticationError` | Access token is invalid or expired |
| 403 | `XeroKiwi::ClientError` | The token doesn't have the required scope |
| 404 | `XeroKiwi::ClientError` | The user ID doesn't exist in this organisation |

## Common patterns

### Listing all users for each tenant

```ruby
client = XeroKiwi::Client.new(access_token: "ya29...")

client.connections.each do |conn|
  users = client.users(conn)
  puts "#{conn.tenant_name}: #{users.size} users"
  users.each { |u| puts "  #{u.first_name} #{u.last_name} (#{u.organisation_role})" }
end
```

### Finding the subscriber

```ruby
users = client.users(tenant_id)
subscriber = users.find(&:subscriber?)
puts "Billing owner: #{subscriber.email_address}" if subscriber
```
