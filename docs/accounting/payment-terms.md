# XeroKiwi::Accounting::PaymentTerms

Default payment terms for an organisation or contact, containing separate
terms for bills (accounts payable) and sales invoices (accounts receivable).

> See: [Xero docs — Payment terms](https://developer.xero.com/documentation/api/accounting/types#paymentterms)

## Usage

```ruby
if org.payment_terms
  bills = org.payment_terms.bills
  sales = org.payment_terms.sales

  puts "Bills due: day #{bills.day} (#{bills.type})" if bills
  puts "Sales due: day #{sales.day} (#{sales.type})" if sales
end
```

## PaymentTerms attributes

| Attribute | Type | Notes |
|-----------|------|-------|
| `bills` | `XeroKiwi::Accounting::PaymentTerm` | Default terms for accounts payable. `nil` if not configured. |
| `sales` | `XeroKiwi::Accounting::PaymentTerm` | Default terms for accounts receivable. `nil` if not configured. |

`PaymentTerms` itself is `nil` on the parent object when the organisation or
contact has no payment terms configured at all.

## PaymentTerm attributes

Each side (bills or sales) is a `XeroKiwi::Accounting::PaymentTerm`:

| Attribute | Type | Notes |
|-----------|------|-------|
| `day` | `Integer` | Day of month (0–31) |
| `type` | `String` | The payment term type (see below) |

### Payment term types

| Type | Meaning |
|------|---------|
| `DAYSAFTERBILLDATE` | Day(s) after bill date |
| `DAYSAFTERBILLMONTH` | Day(s) after bill month |
| `OFCURRENTMONTH` | Of the current month |
| `OFFOLLOWINGMONTH` | Of the following month |

## Equality

Two `PaymentTerms` are `==` if both their `bills` and `sales` are equal. Two
`PaymentTerm` objects are `==` if they share the same `day` and `type`.

## Serialisation

```ruby
org.payment_terms.to_h
# => { bills: { day: 15, type: "OFCURRENTMONTH" }, sales: { day: 20, type: "OFFOLLOWINGMONTH" } }
```
