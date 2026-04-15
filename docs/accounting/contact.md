# Contacts

A Xero **contact** is a person or organisation you do business with — customers,
suppliers, or both. Contacts carry addresses, phone numbers, payment terms, and
metadata like tax type defaults. You need a `tenant_id` from a
[connection](../connections.md) before you can fetch contacts.

> See: [Xero docs — Contacts](https://developer.xero.com/documentation/api/accounting/contacts)

## Listing contacts

```ruby
client = XeroKiwi::Client.new(access_token: "ya29...")

# Pass a tenant ID string…
contacts = client.contacts("70784a63-d24b-46a9-a4db-0e70a274b056")

# …or a XeroKiwi::Connection (its tenant_id is used automatically).
connection = client.connections.first
contacts = client.contacts(connection)
```

`client.contacts` hits `GET /api.xro/2.0/Contacts` with the `Xero-Tenant-Id`
header set to the tenant you specify. It returns an
`Array<XeroKiwi::Accounting::Contact>`.

## Fetching a single contact

```ruby
contact = client.contact(tenant_id, "bd2270c3-8706-4c11-9cfb-000b551c3f51")
contact.name  # => "ABC Limited"
```

`client.contact` hits `GET /api.xro/2.0/Contacts/{ContactID}` and returns a
single `XeroKiwi::Accounting::Contact`, or `nil` if the response is empty.

Fetching a single contact returns additional fields that are not included in the
list response (e.g. `contact_persons`, `payment_terms`, `website`).

## The Contact object

Each `XeroKiwi::Accounting::Contact` is an immutable value object. The fields below
are always returned on list and single-contact responses:

| Attribute | Type | What it is |
|-----------|------|------------|
| `contact_id` | `String` | The unique Xero identifier for the contact. |
| `contact_number` | `String` | External system identifier (read-only in Xero UI). |
| `account_number` | `String` | A user-defined account number. |
| `contact_status` | `String` | `"ACTIVE"` or `"ARCHIVED"`. |
| `name` | `String` | Full name of the contact or organisation. |
| `first_name` | `String` | First name of the contact person. |
| `last_name` | `String` | Last name of the contact person. |
| `email_address` | `String` | Email address of the contact person. |
| `bank_account_details` | `String` | Bank account number. |
| `company_number` | `String` | Company registration number (max 50 chars). |
| `tax_number` | `String` | ABN / GST / VAT / Tax ID Number. |
| `tax_number_type` | `String` | Regional type of tax number (e.g. `"ABN"`). |
| `accounts_receivable_tax_type` | `String` | Default AR invoice tax type. |
| `accounts_payable_tax_type` | `String` | Default AP invoice tax type. |
| `addresses` | `Array<XeroKiwi::Accounting::Address>` | The contact's addresses. See [Address](address.md). |
| `phones` | `Array<XeroKiwi::Accounting::Phone>` | The contact's phone numbers. See [Phone](phone.md). |
| `is_supplier` | `Boolean` | Whether the contact has any AP invoices. |
| `is_customer` | `Boolean` | Whether the contact has any AR invoices. |
| `default_currency` | `String` | Default currency code (e.g. `"NZD"`). |
| `updated_date_utc` | `Time` | When the contact was last modified, parsed as UTC. |

### Additional fields (single contact / paginated responses only)

| Attribute | Type | What it is |
|-----------|------|------------|
| `contact_persons` | `Array<XeroKiwi::Accounting::ContactPerson>` | Up to 5 contact people. See [ContactPerson](#the-contactperson-object). |
| `xero_network_key` | `String` | Xero network key for the contact. |
| `merged_to_contact_id` | `String` | ID of the destination contact if merged. |
| `sales_default_account_code` | `String` | Default sales account code. |
| `purchases_default_account_code` | `String` | Default purchases account code. |
| `sales_tracking_categories` | `Array<Hash>` | Default sales tracking categories (raw). |
| `purchases_tracking_categories` | `Array<Hash>` | Default purchases tracking categories (raw). |
| `sales_default_line_amount_type` | `String` | `"INCLUSIVE"`, `"EXCLUSIVE"`, or `"NONE"`. |
| `purchases_default_line_amount_type` | `String` | `"INCLUSIVE"`, `"EXCLUSIVE"`, or `"NONE"`. |
| `tracking_category_name` | `String` | Tracking category name. |
| `tracking_option_name` | `String` | Tracking option name. |
| `payment_terms` | `XeroKiwi::Accounting::PaymentTerms` | Default payment terms. See [PaymentTerms](payment-terms.md). |
| `contact_groups` | `Array<Hash>` | Contact groups the contact belongs to (raw). |
| `website` | `String` | Website URL. |
| `branding_theme` | `Hash` | Default branding theme (raw). |
| `batch_payments` | `Hash` | Batch payment details (raw). |
| `discount` | `Float` | Default discount rate. |
| `balances` | `Hash` | Outstanding and overdue AR/AP balances (raw). |
| `has_attachments` | `Boolean` | Whether the contact has attachments. |

## The ContactPerson object

Each `XeroKiwi::Accounting::ContactPerson` is an immutable value object:

| Attribute | Type | What it is |
|-----------|------|------------|
| `first_name` | `String` | First name. |
| `last_name` | `String` | Last name. |
| `email_address` | `String` | Email address. |
| `include_in_emails` | `Boolean` | Whether to include on invoice emails. |

With a predicate: `contact_person.include_in_emails?`

## Predicates

```ruby
contact.reference?  # true if this is a lightweight reference from another resource
contact.supplier?   # is_supplier == true
contact.customer?   # is_customer == true
contact.active?     # contact_status == "ACTIVE"
contact.archived?   # contact_status == "ARCHIVED"
```

### Contact references

When a contact appears nested inside another resource (e.g. an Invoice, Prepayment,
or CreditNote), it is wrapped as a `XeroKiwi::Accounting::Contact` with `reference?`
returning `true`. Reference contacts typically carry only a subset of fields (like
`contact_id` and `name`) — other fields will be `nil`.

```ruby
invoice = client.invoice(tenant_id, invoice_id)
invoice.contact.name          # => "City Agency"
invoice.contact.reference?    # => true

# Fetch the full contact if you need all fields:
full_contact = client.contact(tenant_id, invoice.contact.contact_id)
full_contact.reference?       # => false
full_contact.email_address    # => "a.dutchess@abclimited.com"
```

## Equality and hashing

Two contacts are `==` if they share the same `contact_id`. `#hash` is consistent
with `==`, so contacts work as hash keys and in sets.

## Error behaviour

| HTTP status | Exception | What it usually means |
|-------------|-----------|------------------------|
| 200 | (none — returns contacts) | Success |
| 401 | `XeroKiwi::AuthenticationError` | Access token is invalid or expired |
| 403 | `XeroKiwi::ClientError` | The token doesn't have the required scope |
| 404 | `XeroKiwi::ClientError` | The contact ID doesn't exist in this organisation |

## Common patterns

### Listing all customers

```ruby
contacts = client.contacts(tenant_id)
customers = contacts.select(&:customer?)
customers.each { |c| puts "#{c.name} (#{c.default_currency})" }
```

### Fetching a contact with full details

```ruby
# The list response omits some fields. Fetch individually for full details.
contact = client.contact(tenant_id, "bd2270c3-8706-4c11-9cfb-000b551c3f51")
puts contact.website
contact.contact_persons.each do |person|
  puts "  #{person.first_name} #{person.last_name} — #{person.email_address}"
end
```
