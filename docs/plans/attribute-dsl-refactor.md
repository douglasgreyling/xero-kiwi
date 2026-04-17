# Attribute DSL Refactor

## Context

Every accounting resource class in kiwi repeats the same pattern: an
`ATTRIBUTES` name-map constant, an `attr_reader(*ATTRIBUTES.keys)` call, and a
hand-written `initialize` that duplicates hydration logic across nine files.
`parse_time` alone is copy-pasted into every resource. Nested-object and
collection hydration (`Contact.new(attrs, reference: true)`,
`(attrs["LineItems"] || []).map { … }`) follows an identical shape in every
class but is written by hand each time.

This is cheap today but will bite us soon. The upcoming query work
(filtering/sorting/pagination) needs field-type metadata per attribute — adding
a second `FIELDS` constant next to `ATTRIBUTES` would double the duplication.
Writer support down the line will need serialisation metadata too. Both extend
cleanly from a single attribute declaration.

This plan extracts a small `attribute` DSL and migrates every accounting
resource to it. No behaviour change, no public API change — constructors keep
the same signature, existing specs keep passing. It's pure preparation for the
0.3.0 querying work (tracked separately) and for writer support later.

## Decisions locked in

- **Reader-only.** No serialisation/writer concerns in this refactor. DSL
  naming (`attribute`, not `reader` or `field`) leaves room for it later.
- **No query metadata yet.** The `query: true` flag and `query_fields` map
  come with the querying plan — not now. One concern at a time.
- **Public API unchanged.** `Invoice.new(hash, reference: …)` keeps working
  identically. `to_h`, `attr_reader`s, `==`, `hash`, `inspect`, resource-specific
  helper methods (`accounts_receivable?`, etc.) all stay.
- **Every accounting class migrates** — including nested value types
  (`Address`, `Phone`, `LineItem`, `ContactPerson`, `ExternalLink`,
  `PaymentTerm`, any others). Partial migration would leave two patterns
  coexisting, which is worse than either alone.
- **Version: flagged, not decided.** Internal refactor with no public API
  change — defensibly a patch (`0.2.1`). Could also bundle under `0.3.0` since
  that's the version the querying work will ship under and this is its
  foundation. Confirm before bumping.

## Design

### 1. `XeroKiwi::Accounting::Resource` mixin

```ruby
# lib/xero_kiwi/accounting/resource.rb
module XeroKiwi
  module Accounting
    module Resource
      def self.included(base) = base.extend(ClassMethods)

      module ClassMethods
        def payload_key(key) = @payload_key = key

        def attribute(name, xero:, type: :string, of: nil, hydrate: nil)
          attributes[name] = { xero: xero, type: type, of: of, hydrate: hydrate }
          attr_reader name
        end

        def attributes = (@attributes ||= {})

        def from_response(payload)
          return [] if payload.nil?

          items = payload[@payload_key]
          return [] if items.nil?

          items.map { |attrs| new(attrs) }
        end
      end

      def initialize(attrs, reference: false)
        attrs         = attrs.transform_keys(&:to_s)
        @is_reference = reference

        self.class.attributes.each do |name, spec|
          value = Hydrator.call(attrs[spec[:xero]], spec)
          instance_variable_set("@#{name}", value)
        end
      end

      def reference? = @is_reference

      def to_h
        self.class.attributes.keys.to_h { |k| [k, public_send(k)] }
      end
    end
  end
end
```

### 2. `XeroKiwi::Accounting::Hydrator`

Shared hydration dispatch and the single home for `parse_time`.

```ruby
# lib/xero_kiwi/accounting/hydrator.rb
module XeroKiwi
  module Accounting
    module Hydrator
      module_function

      def call(raw, spec)
        return spec[:hydrate].call(raw) if spec[:hydrate]
        return [] if spec[:type] == :collection && raw.nil?
        return nil if raw.nil?

        case spec[:type]
        when :string, :enum, :guid, :bool, :decimal
          raw
        when :date
          parse_time(raw)
        when :object
          spec[:of].new(raw, reference: true)
        when :collection
          raw.map { |item| spec[:of].new(item) }
        else
          raise ArgumentError, "unknown attribute type: #{spec[:type]}"
        end
      end

      def parse_time(value)
        return nil if value.nil?

        str = value.to_s.strip
        return nil if str.empty?

        if (match = str.match(%r{\A/Date\((\d+)([+-]\d{4})?\)/\z}))
          Time.at(match[1].to_i / 1000.0).utc
        else
          str = "#{str}Z" unless str.match?(/[Zz]\z|[+-]\d{2}:?\d{2}\z/)
          Time.iso8601(str)
        end
      rescue ArgumentError
        nil
      end
    end
  end
end
```

### 3. Supported attribute types

| Type          | Hydrates to                                     | Notes                                      |
|---------------|-------------------------------------------------|--------------------------------------------|
| `:string`     | value as-is                                     | default                                    |
| `:enum`       | value as-is                                     | semantic marker for future validation      |
| `:guid`       | value as-is                                     | semantic marker for future query typing    |
| `:bool`       | value as-is                                     |                                            |
| `:decimal`    | value as-is                                     | Xero returns these as numbers or strings   |
| `:date`       | `Time` via `Hydrator.parse_time`                | handles `/Date(ms)/` and ISO8601           |
| `:object`     | `spec[:of].new(raw, reference: true)`           | requires `of:`                             |
| `:collection` | `raw.map { spec[:of].new(item) }`, `nil` → `[]` | requires `of:`                             |

Escape hatch: `hydrate: ->(raw) { … }` for one-off fields the built-in types
can't express. Runs before dispatch.

### 4. Before / after (example)

Invoice before — 40+ lines of `initialize`, `parse_time` method, `ATTRIBUTES`
constant duplicated:

```ruby
ATTRIBUTES = { invoice_id: "InvoiceID", … }.freeze
attr_reader(*ATTRIBUTES.keys)

def initialize(attrs, reference: false)
  attrs                = attrs.transform_keys(&:to_s)
  @is_reference        = reference
  @invoice_id          = attrs["InvoiceID"]
  @invoice_number      = attrs["InvoiceNumber"]
  @contact             = attrs["Contact"] ? Contact.new(attrs["Contact"], reference: true) : nil
  @date                = parse_time(attrs["Date"])
  @line_items          = (attrs["LineItems"] || []).map { |li| LineItem.new(li) }
  # … 30 more lines …
end

private

def parse_time(value)
  # … 15 lines, duplicated in 9 files …
end
```

After — one declaration per field, no `initialize`, no `parse_time`:

```ruby
include Accounting::Resource

payload_key "Invoices"

attribute :invoice_id,     xero: "InvoiceID",     type: :guid
attribute :invoice_number, xero: "InvoiceNumber", type: :string
attribute :contact,        xero: "Contact",       type: :object,     of: Contact
attribute :date,           xero: "Date",          type: :date
attribute :line_items,     xero: "LineItems",     type: :collection, of: LineItem
# …

def accounts_receivable? = type == "ACCREC"
def accounts_payable?    = type == "ACCPAY"

def ==(other) = other.is_a?(Invoice) && other.invoice_id == invoice_id
alias eql? ==
def hash = [self.class, invoice_id].hash
```

### 5. Edge cases to preserve

- **Raw pass-through fields** that are currently kept as plain hashes/arrays
  (e.g. `Invoice#invoice_addresses`, `Contact#bank_account_details`) — use
  `type: :string` (misnomer but harmless) or the `hydrate:` escape hatch with
  an identity lambda. Audit each during migration.
- **`reference: true` semantics** — nested `:object` attributes always hydrate
  with `reference: true`; nested `:collection` attributes hydrate without it
  (full objects). This matches today's behaviour per-file. If any class
  currently deviates, that deviation gets a `hydrate:` escape hatch.
- **Resource-specific helpers** (`accounts_receivable?`, `reference?`,
  `inspect`, `==`, `hash`) stay inline on each class.
- **Classes without list endpoints** (nested value types — `Address`, `Phone`,
  etc.) use the DSL but don't call `payload_key`. `from_response` on them isn't
  called; the method existing but unused is harmless.

## Files

### Create

- `lib/xero_kiwi/accounting/resource.rb` — the DSL mixin.
- `lib/xero_kiwi/accounting/hydrator.rb` — shared hydration + `parse_time`.
- `spec/xero_kiwi/accounting/resource_spec.rb` — DSL unit tests.
- `spec/xero_kiwi/accounting/hydrator_spec.rb` — hydrator unit tests.

### Modify

- `lib/xero_kiwi.rb` — `require` the new files before any accounting class.
- Every `lib/xero_kiwi/accounting/*.rb` — migrate to `attribute` DSL, drop
  `ATTRIBUTES`, drop hand-written `initialize`, drop private `parse_time`.
  Concrete list: `contact.rb`, `contact_group.rb`, `contact_person.rb`,
  `invoice.rb`, `credit_note.rb`, `prepayment.rb`, `overpayment.rb`,
  `payment.rb`, `user.rb`, `branding_theme.rb`, `organisation.rb`, `address.rb`,
  `phone.rb`, `external_link.rb`, `payment_term.rb`, `line_item.rb`, and any
  other value classes in `lib/xero_kiwi/accounting/`.
- `lib/xero_kiwi/version.rb` — bump (0.2.1 or 0.3.0 — confirm).
- `CHANGELOG.md` — **Changed** entry describing the internal refactor.
- `Gemfile.lock` — rebuild after version bump.

## Testing strategy

- **Hydrator unit specs:** each type dispatches correctly. `/Date(ms)/` parses.
  ISO8601 with and without timezone parses. Empty/invalid strings return
  `nil`. `:object` hydrates nested reference. `:collection` with `nil` →
  `[]`, populated → `map`ped. `:collection` with `nil` + `hydrate:` runs the
  lambda. Unknown type raises.
- **Resource unit specs:** declare a throwaway class inside the spec with a
  couple of attributes of each type, hydrate a fixture hash, assert every
  reader returns the expected value, `to_h` returns a keyed hash, `payload_key`
  + `from_response` parse an envelope.
- **Existing accounting resource specs carry the real load.** They already
  call `Class.new(fixture_hash)` and assert every reader — they should pass
  unchanged. A regression in the DSL surfaces as real-resource spec failures,
  which is exactly what we want.
- **Client integration specs** — untouched, must still pass green.

## Verification

```sh
bundle install
bundle exec rspec                              # full suite green
bundle exec rspec spec/xero_kiwi/accounting    # DSL + hydrator + every resource
bundle exec rspec spec/xero_kiwi/client_spec.rb # list methods unaffected
bundle exec rubocop                            # style still clean
```

Smoke check in IRB against a recorded fixture or live tenant:

```ruby
require "xero_kiwi"

client = XeroKiwi::Client.new(access_token: ENV.fetch("XERO_TOKEN"))
invoices = client.invoices(tenant)
inv = invoices.first

inv.invoice_id            # string
inv.date                  # Time
inv.contact               # Accounting::Contact, reference? == true
inv.line_items            # Array<Accounting::LineItem>
inv.to_h.keys             # every attribute name
```

## Follow-up

Once this lands, the 0.3.0 querying plan picks up by:

1. Adding a `query: true` option to `attribute`.
2. Auto-populating `query_fields` on the class from attributes flagged
   queryable.
3. Building `Query::Filter` / `Query::Order` compilers against that map.
4. Adding the `Page` return type, `each_*` helpers, and `modified_since`
   support on the client.

None of which requires re-touching the resource files.
