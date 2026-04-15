# XeroKiwi::Accounting::ExternalLink

A Xero external link (social or web profile). Used by
[Organisation](organisation.md).

> See: [Xero docs — External link types](https://developer.xero.com/documentation/api/accounting/types#externallinks)

## Usage

```ruby
org.external_links.each do |link|
  puts "#{link.link_type}: #{link.url}"
end
```

## Attributes

| Attribute | Type | Notes |
|-----------|------|-------|
| `link_type` | `String` | `"Facebook"`, `"GooglePlus"`, `"LinkedIn"`, `"Twitter"`, or `"Website"` |
| `url` | `String` | The URL for the service |

## Equality

Two external links are `==` if all their attributes match. `#hash` is
consistent with `==`.

## Serialisation

```ruby
link.to_h
# => { link_type: "Facebook", url: "https://facebook.com/example" }
```
