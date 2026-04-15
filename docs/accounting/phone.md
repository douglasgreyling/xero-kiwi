# XeroKiwi::Accounting::Phone

A Xero phone number. Used by [Organisation](organisation.md), and in future by
Contact and other resources.

> See: [Xero docs — Phone types](https://developer.xero.com/documentation/api/accounting/types#phones)

## Usage

```ruby
org.phones.each do |phone|
  puts "#{phone.phone_type}: #{phone.phone_country_code} #{phone.phone_area_code} #{phone.phone_number}"
end

mobile = org.phones.find(&:mobile?)
```

## Attributes

| Attribute | Type | Notes |
|-----------|------|-------|
| `phone_type` | `String` | `"DEFAULT"`, `"DDI"`, `"MOBILE"`, or `"FAX"` |
| `phone_number` | `String` | Max 50 characters |
| `phone_area_code` | `String` | Max 10 characters |
| `phone_country_code` | `String` | Max 20 characters |

## Predicates

```ruby
phone.default? # phone_type == "DEFAULT"
phone.mobile?  # phone_type == "MOBILE"
phone.fax?     # phone_type == "FAX"
```

## Equality

Two phones are `==` if all their attributes match. `#hash` is consistent
with `==`.

## Serialisation

```ruby
phone.to_h
# => { phone_type: "DEFAULT", phone_number: "1234567", phone_area_code: "09", phone_country_code: "64" }
```
