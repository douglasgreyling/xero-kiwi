# Organisation

A Xero **organisation** is the actual accounting entity — the company, sole
trader, trust, etc. that owns the books. You need a `tenant_id` from a
[connection](../connections.md) before you can fetch one.

> See: [Xero docs — Organisation](https://developer.xero.com/documentation/api/accounting/organisation)

## Fetching an organisation

```ruby
client = XeroKiwi::Client.new(access_token: "ya29...")

# Pass a tenant ID string…
org = client.organisation("70784a63-d24b-46a9-a4db-0e70a274b056")

# …or a XeroKiwi::Connection (its tenant_id is used automatically).
connection = client.connections.first
org = client.organisation(connection)
```

`client.organisation` hits `GET /api.xro/2.0/Organisation` with the
`Xero-Tenant-Id` header set to the tenant you specify. It returns a single
`XeroKiwi::Accounting::Organisation`.

## The Organisation object

Each `XeroKiwi::Accounting::Organisation` is an immutable value object exposing the fields
Xero returns:

| Attribute | Type | What it is |
|-----------|------|------------|
| `organisation_id` | `String` | The unique identifier for the organisation. |
| `api_key` | `String` | The API key (if set). |
| `name` | `String` | The display name (e.g. "Maple Florists Ltd"). |
| `legal_name` | `String` | The registered legal name. |
| `pays_tax` | `Boolean` | Whether the organisation is registered for tax. |
| `version` | `String` | The Xero edition version code (e.g. `"NZ"`, `"GLOBAL"`). |
| `organisation_type` | `String` | The type — `"COMPANY"`, `"SOLE_TRADER"`, `"TRUST"`, etc. |
| `base_currency` | `String` | The base currency code (e.g. `"NZD"`, `"ZAR"`). |
| `country_code` | `String` | The two-letter country code (e.g. `"NZ"`, `"ZA"`). |
| `is_demo_company` | `Boolean` | Whether this is a Xero demo company. |
| `organisation_status` | `String` | `"ACTIVE"` or otherwise. |
| `registration_number` | `String` | The company registration number. |
| `employer_identification_number` | `String` | The EIN (US organisations). |
| `tax_number` | `String` | The tax/VAT number. |
| `financial_year_end_day` | `Integer` | Day of month the financial year ends (1–31). |
| `financial_year_end_month` | `Integer` | Month the financial year ends (1–12). |
| `sales_tax_basis` | `String` | e.g. `"Payments"`, `"CASH"`, `"ACCRUALS"`. |
| `sales_tax_period` | `String` | e.g. `"TWOMONTHS"`, `"MONTHLY"`. |
| `default_sales_tax` | `String` | e.g. `"Tax Exclusive"`. |
| `default_purchases_tax` | `String` | e.g. `"Tax Exclusive"`. |
| `period_lock_date` | `Time` | The period lock date, parsed as UTC. |
| `end_of_year_lock_date` | `Time` | The end-of-year lock date, parsed as UTC. |
| `created_date_utc` | `Time` | When the organisation was created, parsed as UTC. |
| `timezone` | `String` | The organisation's timezone code (e.g. `"NEWZEALANDSTANDARDTIME"`). |
| `organisation_entity_type` | `String` | The entity type (e.g. `"COMPANY"`). |
| `short_code` | `String` | The Xero short code for this organisation. |
| `organisation_class` | `String` | The Xero subscription class (e.g. `"PREMIUM"`, `"STARTER"`). |
| `edition` | `String` | The Xero subscription edition (e.g. `"BUSINESS"`). |
| `line_of_business` | `String` | The industry / line of business. |
| `addresses` | `Array<XeroKiwi::Accounting::Address>` | The organisation's addresses. See [Address](address.md). |
| `phones` | `Array<XeroKiwi::Accounting::Phone>` | The organisation's phone numbers. See [Phone](phone.md). |
| `external_links` | `Array<XeroKiwi::Accounting::ExternalLink>` | Social/web profile links. See [ExternalLink](external-link.md). |
| `payment_terms` | `XeroKiwi::Accounting::PaymentTerms` | Default payment terms for bills and sales. See [PaymentTerms](payment-terms.md). |

## Predicates

```ruby
org.demo_company? # is_demo_company == true
```

## Equality and hashing

Two organisations are `==` if they share the same `organisation_id`. `#hash`
is consistent with `==`, so organisations work as hash keys and in sets.

## Date parsing

The Xero Accounting API serialises timestamps differently from the Connections
API. Connections use ISO 8601 strings (e.g. `"2019-07-09T23:40:30.1833130"`),
but the Accounting API (including Organisation) uses the legacy .NET JSON
format: `/Date(1574275974000)/`.

XeroKiwi handles both transparently — all `Time` attributes are parsed to UTC
`Time` objects regardless of which format Xero sends. You don't need to think
about this unless you're looking at raw cassette data or debugging timestamp
issues.

## Error behaviour

| HTTP status | Exception | What it usually means |
|-------------|-----------|------------------------|
| 200 | (none — returns the organisation) | Success |
| 401 | `XeroKiwi::AuthenticationError` | Access token is invalid or expired |
| 403 | `XeroKiwi::ClientError` | The token doesn't have the `accounting.settings.read` scope |
| 404 | `XeroKiwi::ClientError` | The tenant ID doesn't correspond to an organisation |

## Common patterns

### From connection to organisation

```ruby
client = XeroKiwi::Client.new(access_token: "ya29...")

client.connections.each do |conn|
  org = client.organisation(conn)
  puts "#{org.name} (#{org.base_currency}) — #{org.country_code}"
end
```

### Checking if it's a demo company

```ruby
org = client.organisation(tenant_id)
if org.demo_company?
  puts "This is a demo company — data isn't real"
end
```
