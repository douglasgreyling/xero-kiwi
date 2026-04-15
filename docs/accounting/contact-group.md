# Contact Groups

A Xero **contact group** is a named collection of contacts — useful for
organising customers or suppliers into categories like "VIP Customers" or
"Preferred Suppliers". You need a `tenant_id` from a
[connection](../connections.md) before you can fetch contact groups.

> See: [Xero docs — Contact Groups](https://developer.xero.com/documentation/api/accounting/contactgroups)

## Listing contact groups

```ruby
client = XeroKiwi::Client.new(access_token: "ya29...")

# Pass a tenant ID string…
groups = client.contact_groups("70784a63-d24b-46a9-a4db-0e70a274b056")

# …or a XeroKiwi::Connection (its tenant_id is used automatically).
connection = client.connections.first
groups = client.contact_groups(connection)
```

`client.contact_groups` hits `GET /api.xro/2.0/ContactGroups` with the
`Xero-Tenant-Id` header set to the tenant you specify. It returns an
`Array<XeroKiwi::Accounting::ContactGroup>`. Only groups with status `ACTIVE` are
returned by Xero.

## Fetching a single contact group

```ruby
group = client.contact_group(tenant_id, "97bbd0e6-ab4d-4117-9304-d90dd4779199")
group.name      # => "VIP Customers"
group.contacts  # => [{"ContactID" => "...", "Name" => "Boom FM"}, ...]
```

`client.contact_group` hits `GET /api.xro/2.0/ContactGroups/{ContactGroupID}`
and returns a single `XeroKiwi::Accounting::ContactGroup`, or `nil` if the
response is empty.

The single-group response includes a `contacts` array with the `ContactID` and
`Name` of each contact in the group. The list response does not include this.

## The ContactGroup object

Each `XeroKiwi::Accounting::ContactGroup` is an immutable value object exposing the
fields Xero returns:

| Attribute | Type | What it is |
|-----------|------|------------|
| `contact_group_id` | `String` | The unique Xero identifier for the group. |
| `name` | `String` | The display name (e.g. "VIP Customers"). |
| `status` | `String` | `"ACTIVE"` (only active groups are returned by Xero). |
| `contacts` | `Array<XeroKiwi::Accounting::Contact>` | The contacts in the group (references — each has `reference?` returning `true`). Only present when fetching a single group. See [Contacts](contact.md). |

## Predicates

```ruby
group.active?  # status == "ACTIVE"
```

## Equality and hashing

Two contact groups are `==` if they share the same `contact_group_id`. `#hash`
is consistent with `==`, so contact groups work as hash keys and in sets.

## Error behaviour

| HTTP status | Exception | What it usually means |
|-------------|-----------|------------------------|
| 200 | (none — returns groups) | Success |
| 401 | `XeroKiwi::AuthenticationError` | Access token is invalid or expired |
| 403 | `XeroKiwi::ClientError` | The token doesn't have the required scope |
| 404 | `XeroKiwi::ClientError` | The contact group ID doesn't exist |

## Common patterns

### Listing all contact groups

```ruby
groups = client.contact_groups(tenant_id)
groups.each { |g| puts g.name }
```

### Fetching members of a group

```ruby
group = client.contact_group(tenant_id, "97bbd0e6-ab4d-4117-9304-d90dd4779199")
group.contacts.each do |c|
  puts "#{c.name} (#{c.contact_id})"
end
```
