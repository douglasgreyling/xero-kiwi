# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Mixin that gives an accounting resource class a declarative `attribute`
    # DSL. One declaration per field drives reader generation, hydration (via
    # Hydrator), `to_h`, `from_response`, `==` / `eql?` / `hash`, and
    # ActiveRecord-style `inspect`.
    #
    # Usage:
    #
    #   class Invoice
    #     include Accounting::Resource
    #
    #     payload_key "Invoices"
    #     identity :invoice_id        # two Invoices are equal iff invoice_id matches
    #
    #     attribute :invoice_id, xero: "InvoiceID", type: :guid
    #     attribute :date,       xero: "Date",      type: :date
    #     attribute :contact,    xero: "Contact",   type: :object,
    #                            of: Contact, reference: true
    #     attribute :line_items, xero: "LineItems", type: :collection, of: LineItem
    #   end
    #
    # Resources with a server-side primary key (Invoice, Contact, Payment, …)
    # declare `identity :xxx_id`. Value types without a stable ID (Address,
    # Phone, LineItem, …) omit `identity` and fall back to structural equality
    # (every attribute must match).
    module Resource
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def payload_key(key = nil)
          return @payload_key if key.nil?

          @payload_key = key
        end

        # `xero:` takes an Array when the key Xero sends is genuinely in
        # doubt — the first one present in the payload wins. Reach for it
        # only when there is no recorded payload to settle the question and
        # the sources disagree; a wrong single key reads nil forever and
        # looks exactly like a field the tenant never fills.
        def attribute(name, xero:, type: :string, of: nil, reference: false, hydrate: nil, query: false)
          attributes[name] = {
            xero:      xero,
            type:      type,
            of:        of,
            reference: reference,
            hydrate:   hydrate,
            query:     query
          }

          attr_reader name
        end

        def attributes
          @_attributes ||= {}
        end

        # Every key this attribute will answer to, in precedence order.
        def xero_keys(spec)
          Array(spec[:xero])
        end

        # The first candidate key actually present in the payload.
        def raw_value(attrs, spec)
          key = xero_keys(spec).find { |candidate| attrs.key?(candidate) }
          key && attrs[key]
        end

        def identity(*attrs)
          @identity_attributes = attrs.freeze
        end

        def identity_attributes
          @identity_attributes
        end

        # The queryable schema for this resource: the subset of attributes
        # that can appear in Xero's `where` / `order` query params. Any
        # attribute declared with `query: true` is included, and every
        # `identity` attribute is implicitly queryable (resources always
        # filter by their primary key).
        #
        # For `:object` attributes, the child's own `query_fields` is
        # included as a nested schema so callers can filter on e.g.
        # `contact: { contact_id: "..." }`, which the compiler renders as
        # `Contact.ContactID==guid("...")`.
        def query_fields
          @_query_fields ||= attributes.each_with_object({}) do |(name, spec), acc|
            next unless queryable?(name, spec)

            acc[name] = build_query_field(spec)
          end
        end

        private

        def queryable?(name, spec)
          spec[:query] || identity_attributes&.include?(name)
        end

        def build_query_field(spec)
          klass = spec[:of].is_a?(Class) ? spec[:of] : (spec[:of] && Hydrator.resolve_class(spec[:of]))

          path = xero_keys(spec).first

          if spec[:type] == :object && klass.respond_to?(:query_fields)
            { path: path, type: :nested, fields: klass.query_fields }
          else
            { path: path, type: spec[:type] }
          end
        end

        public

        # `opts[:retain_raw]` is threaded down from Client#initialize. It
        # applies to the resources built here and not to their nested
        # objects — the top-level `raw` hash already holds every nested
        # payload verbatim, so `contact.raw["ContactPersons"]` gets there
        # without pushing the flag through Hydrator and every build_object
        # call.
        #
        # `opts` is positional for the same reason it is on #initialize: a
        # bare string-keyed payload (`from_response("Users" => [])`) would
        # otherwise be swallowed as keyword arguments in Ruby 3, leaving
        # `payload` unset.
        def from_response(payload, opts = {})
          return [] if payload.nil?

          items = payload[payload_key]
          return [] if items.nil?

          items.map { |attrs| new(attrs, retain_raw: opts[:retain_raw]) }
        end
      end

      # `opts` is positional, not a kwarg, so that bare string-keyed hashes
      # (`Klass.new("Foo" => "bar")`) don't get silently absorbed as kwargs in
      # Ruby 3. Callers passing `reference: true` land here as a positional
      # symbol-keyed hash, which is what we want.
      def initialize(attrs, opts = {})
        attrs         = attrs.transform_keys(&:to_s)
        @is_reference = opts[:reference] == true
        @raw          = opts[:retain_raw] ? attrs.freeze : nil

        self.class.attributes.each do |name, spec|
          value = Hydrator.call(self.class.raw_value(attrs, spec), spec)
          instance_variable_set("@#{name}", value)
        end
      end

      # This resource's own hash from Xero's JSON response, exactly as it
      # arrived, or nil unless the client was built with `retain_raw: true`.
      # Use it to reach fields the gem doesn't model.
      #
      # Returns nil on NESTED objects even when retain_raw is on — line
      # items, addresses, contact persons, payment terms. Reach those
      # through the enclosing resource instead:
      #
      #   org.addresses.map(&:raw)  # => [nil]
      #   org.raw["Addresses"]      # => [{"AddressType" => "POBOX", ...}]
      #
      # Scope is the item, NOT the enclosing envelope: `contact.raw` has no
      # "Contacts" key, and `organisation.raw` no "Organisations" key. Kiwi
      # unwraps the envelope before a resource is built, so there is nothing
      # left of it by the time this is populated.
      #
      # Kiwi never normalises what it stores here: absent keys stay absent
      # rather than becoming [] or nil entries, and keys the gem doesn't
      # model are preserved. The hash itself is frozen; the structures
      # nested inside it are not.
      #
      # It is also the JSON representation specifically. Kiwi sends
      # `Accept: application/json`; Xero's XML representation nests
      # differently — no arrays, so one child is a Hash and several are an
      # Array — and `raw` cannot reproduce that shape. Worth knowing when
      # migrating off an XML-based Xero client with stored payloads.
      #
      # Note `to_h` is NOT this — it's a snake_case projection rebuilt from
      # the modelled attributes, with different keys and different nesting.
      attr_reader :raw

      def reference?
        @is_reference
      end

      def to_h
        self.class.attributes.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        return false unless other.is_a?(self.class)

        ids = self.class.identity_attributes
        if ids && !ids.empty?
          ids.all? { |attr| public_send(attr) == other.public_send(attr) }
        else
          to_h == other.to_h
        end
      end
      alias eql? ==

      def hash
        ids = self.class.identity_attributes
        if ids && !ids.empty?
          [self.class, *ids.map { |attr| public_send(attr) }].hash
        else
          [self.class, to_h].hash
        end
      end

      # ActiveRecord-style inspect: shows every declared attribute inline.
      # Nested objects collapse to a one-line reference (identity-only when
      # available, otherwise just the class name) so cascades don't explode.
      # Collections collapse to `[N items]`.
      def inspect
        pairs = self.class.attributes.map { |name, spec| "#{name}=#{format_for_inspect(public_send(name), spec)}" }
        "#<#{self.class} #{pairs.join(" ")}>"
      end

      private

      def format_for_inspect(value, spec)
        case spec[:type]
        when :collection
          "[#{value.size} items]"
        when :object
          value.nil? ? "nil" : format_nested_object(value)
        when :decimal
          value.nil? ? "nil" : value.to_s("F")
        else
          value.inspect
        end
      end

      def format_nested_object(obj) # rubocop:disable Metrics/AbcSize
        short = (obj.class.name || obj.class.to_s).split("::").last
        ids   = obj.class.respond_to?(:identity_attributes) ? obj.class.identity_attributes : nil

        if ids && !ids.empty?
          id_pairs = ids.map { |a| "#{a}=#{obj.public_send(a).inspect}" }.join(" ")
          "#<#{short} #{id_pairs}>"
        else
          "#<#{short}>"
        end
      end
    end
  end
end
