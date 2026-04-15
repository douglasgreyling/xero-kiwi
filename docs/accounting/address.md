# XeroKiwi::Accounting::Address

A Xero address. Used by [Organisation](organisation.md), and in future by
Contact and other resources.

> See: [Xero docs — Address types](https://developer.xero.com/documentation/api/accounting/types#addresses)

## Usage

```ruby
org.addresses.each do |address|
  puts "#{address.address_type}: #{address.address_line_1}, #{address.city}"
end

street = org.addresses.find(&:street?)
```

## Attributes

| Attribute | Type | Notes |
|-----------|------|-------|
| `address_type` | `String` | `"POBOX"`, `"STREET"`, or `"DELIVERY"` |
| `address_line_1` | `String` | Max 500 characters |
| `address_line_2` | `String` | Max 500 characters |
| `address_line_3` | `String` | Max 500 characters |
| `address_line_4` | `String` | Max 500 characters |
| `city` | `String` | Max 255 characters |
| `region` | `String` | Max 255 characters |
| `postal_code` | `String` | Max 50 characters |
| `country` | `String` | Max 50 characters, letters only |
| `attention_to` | `String` | Max 255 characters |

## Predicates

```ruby
address.street?   # address_type == "STREET"
address.pobox?    # address_type == "POBOX"
address.delivery? # address_type == "DELIVERY"
```

Note: `DELIVERY` is read-only via Xero's GET endpoint (if set) and is not
valid for Contacts — only for Organisations.

## Equality

Two addresses are `==` if all their attributes match. `#hash` is consistent
with `==`.

## Serialisation

```ruby
address.to_h
# => { address_type: "STREET", address_line_1: "123 Main St", ... }
```
