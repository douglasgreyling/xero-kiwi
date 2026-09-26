# Tracking Categories

Xero **tracking categories** let an organisation tag transactions along its
own dimensions — Region, Department, Cost Centre. Each category holds a set
of options (Eastside, Westside), and a line item picks at most one option
per category. An organisation can have at most two active categories.

You need a `tenant_id` from a [connection](../connections.md) before you can
fetch tracking categories.

> See: [Xero docs — Tracking Categories](https://developer.xero.com/documentation/api/accounting/trackingcategories)

## Two shapes, two classes

Xero uses the phrase "tracking category" for two different things, and kiwi
models them as two separate classes. Getting these mixed up is the most
common confusion here, so it's worth being explicit.

**`XeroKiwi::Accounting::TrackingCategory`** — the *definition*, returned by
`GET /TrackingCategories`. The category plus every option available under it.

```json
{ "TrackingCategoryID": "abc", "Name": "Region", "Status": "ACTIVE",
  "Options": [ { "TrackingOptionID": "def", "Name": "Eastside", "Status": "ACTIVE" } ] }
```

**`XeroKiwi::Accounting::Tracking`** — the *assignment*, nested on a line
item (Xero's own field name for it is `Tracking`) or a contact. One category
and the single option chosen for it, flattened.

```json
{ "TrackingCategoryID": "abc", "TrackingOptionID": "def",
  "Name": "Region", "Option": "Eastside" }
```

They share a name and one ID field and nothing else. If you're reading
`invoice.line_items.first.tracking`, you have `Tracking` objects. If you
called `client.tracking_categories`, you have `TrackingCategory` objects.

## Listing tracking categories

```ruby
client = XeroKiwi::Client.new(access_token: "ya29...")

categories = client.tracking_categories(tenant_id)

categories.first.name             # => "Region"
categories.first.options.map(&:name)  # => ["Eastside", "Westside"]
```

`client.tracking_categories` hits `GET /api.xro/2.0/TrackingCategories` with
the `Xero-Tenant-Id` header set, and returns a `XeroKiwi::Page` of
`TrackingCategory` objects.

This endpoint isn't paged — an organisation has at most two active
categories. `each_tracking_category` exists so all ten list resources behave
consistently, but there's no reason to reach for it over the plain call.

## Fetching a single category

```ruby
category = client.tracking_category(tenant_id, "e2f2f732-e92a-4f3a-9c4d-ee4da0182a13")
category.name  # => "Region"
```

Hits `GET /api.xro/2.0/TrackingCategories/{TrackingCategoryID}` and returns a
single `TrackingCategory`, or `nil` if the response is empty.

## The TrackingCategory object

| Attribute | Type | What it is |
|-----------|------|------------|
| `tracking_category_id` | `String` | The unique Xero identifier for the category. |
| `name` | `String` | The category's display name (e.g. "Region"). |
| `status` | `String` | `"ACTIVE"` or `"ARCHIVED"`. |
| `options` | `Array<TrackingOption>` | The options available under this category. Empty array when absent. |

`#active?` is a shorthand for `status == "ACTIVE"`.

## The TrackingOption object

| Attribute | Type | What it is |
|-----------|------|------------|
| `tracking_option_id` | `String` | The unique Xero identifier for the option. |
| `name` | `String` | The option's display name (e.g. "Eastside"). |
| `status` | `String` | `"ACTIVE"` or `"DELETED"`. |

`#active?` is a shorthand for `status == "ACTIVE"`.

## The Tracking object

The assignment shape, nested on line items and contacts.

| Attribute | Type | What it is |
|-----------|------|------------|
| `tracking_category_id` | `String` | Which category this assignment is for. |
| `tracking_option_id` | `String` | Which option was chosen. |
| `name` | `String` | The category's name, denormalised by Xero. |
| `option` | `String` | The chosen option's name, denormalised by Xero. |

## Querying

`name` and `status` are queryable on both `TrackingCategory` and
`TrackingOption`, as is the identity field.

```ruby
client.tracking_categories(tenant_id, where: { status: "ACTIVE" })
```

## Equality and hashing

Two `TrackingCategory` objects are `==` if they share the same
`tracking_category_id`; two `TrackingOption` objects if they share the same
`tracking_option_id`. `Tracking` has no server-side primary key of its own,
so it falls back to structural equality — every attribute must match.

## Error behaviour

| HTTP status | Exception | What it usually means |
|-------------|-----------|------------------------|
| 200 | (none — returns categories) | Success |
| 401 | `XeroKiwi::AuthenticationError` | Access token is invalid or expired |
| 403 | `XeroKiwi::ClientError` | The token doesn't have the `accounting.settings` scope |
| 404 | `XeroKiwi::ClientError` | The tracking category ID doesn't exist in this organisation |

## Common patterns

### Building a lookup from option ID to names

Line items carry only IDs and denormalised names; if you need the canonical
option list, fetch the definitions once per sync and index them.

```ruby
options = client.tracking_categories(tenant_id).flat_map do |category|
  category.options.map { |option| [option.tracking_option_id, [category.name, option.name]] }
end.to_h

invoice.line_items.each do |line|
  line.tracking.each do |assignment|
    category_name, option_name = options.fetch(assignment.tracking_option_id)
    puts "#{category_name}: #{option_name}"
  end
end
```

### Ignoring archived categories

```ruby
active = client.tracking_categories(tenant_id).select(&:active?)
```
