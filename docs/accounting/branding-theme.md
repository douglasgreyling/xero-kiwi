# Branding Themes

A Xero **branding theme** controls the look and feel of invoices, quotes, and
other documents — logo, colours, layout. Every organisation has at least one
(the default "Standard" theme). You need a `tenant_id` from a
[connection](../connections.md) before you can fetch branding themes.

> See: [Xero docs — Branding Themes](https://developer.xero.com/documentation/api/accounting/brandingthemes)

## Listing branding themes

```ruby
client = XeroKiwi::Client.new(access_token: "ya29...")

# Pass a tenant ID string…
themes = client.branding_themes("70784a63-d24b-46a9-a4db-0e70a274b056")

# …or a XeroKiwi::Connection (its tenant_id is used automatically).
connection = client.connections.first
themes = client.branding_themes(connection)
```

`client.branding_themes` hits `GET /api.xro/2.0/BrandingThemes` with the
`Xero-Tenant-Id` header set to the tenant you specify. It returns an
`Array<XeroKiwi::Accounting::BrandingTheme>`.

## Fetching a single branding theme

```ruby
theme = client.branding_theme(tenant_id, "dfe23d27-a3a6-4ef3-a5ca-b9e02b142dde")
theme.name  # => "Special Projects"
```

`client.branding_theme` hits `GET /api.xro/2.0/BrandingThemes/{BrandingThemeID}`
and returns a single `XeroKiwi::Accounting::BrandingTheme`, or `nil` if the
response is empty.

## The BrandingTheme object

Each `XeroKiwi::Accounting::BrandingTheme` is an immutable value object exposing the
fields Xero returns:

| Attribute | Type | What it is |
|-----------|------|------------|
| `branding_theme_id` | `String` | The unique Xero identifier for the branding theme. |
| `name` | `String` | The display name (e.g. "Standard", "Special Projects"). |
| `logo_url` | `String` | The URL of the logo image used on the theme. May be `nil` if no custom logo is set. |
| `type` | `String` | The document type the theme applies to (always `"INVOICE"`). |
| `sort_order` | `Integer` | Ranked order of the theme. The default theme has a value of `0`. |
| `created_date_utc` | `Time` | When the theme was created, parsed as UTC. |

## Equality and hashing

Two branding themes are `==` if they share the same `branding_theme_id`.
`#hash` is consistent with `==`, so branding themes work as hash keys and in
sets.

## Date parsing

The `created_date_utc` field uses Xero's .NET JSON timestamp format
(`/Date(946684800000+0000)/`). Xero Kiwi parses both .NET JSON and ISO 8601
formats transparently — the attribute is always a UTC `Time` object.

## Error behaviour

| HTTP status | Exception | What it usually means |
|-------------|-----------|------------------------|
| 200 | (none — returns themes) | Success |
| 401 | `XeroKiwi::AuthenticationError` | Access token is invalid or expired |
| 403 | `XeroKiwi::ClientError` | The token doesn't have the required scope |
| 404 | `XeroKiwi::ClientError` | The branding theme ID doesn't exist in this organisation |

## Common patterns

### Listing all themes for a tenant

```ruby
client = XeroKiwi::Client.new(access_token: "ya29...")

themes = client.branding_themes(tenant_id)
themes.each do |theme|
  puts "#{theme.name} (sort: #{theme.sort_order})"
end
```

### Finding the default theme

```ruby
themes  = client.branding_themes(tenant_id)
default = themes.find { |t| t.sort_order == 0 }
puts "Default theme: #{default.name}"
```
