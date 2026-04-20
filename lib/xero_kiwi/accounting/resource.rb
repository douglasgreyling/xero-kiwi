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

          if spec[:type] == :object && klass.respond_to?(:query_fields)
            { path: spec[:xero], type: :nested, fields: klass.query_fields }
          else
            { path: spec[:xero], type: spec[:type] }
          end
        end

        public

        def from_response(payload)
          return [] if payload.nil?

          items = payload[payload_key]
          return [] if items.nil?

          items.map { |attrs| new(attrs) }
        end
      end

      # `opts` is positional, not a kwarg, so that bare string-keyed hashes
      # (`Klass.new("Foo" => "bar")`) don't get silently absorbed as kwargs in
      # Ruby 3. Callers passing `reference: true` land here as a positional
      # symbol-keyed hash, which is what we want.
      def initialize(attrs, opts = {})
        attrs         = attrs.transform_keys(&:to_s)
        @is_reference = opts[:reference] == true

        self.class.attributes.each do |name, spec|
          value = Hydrator.call(attrs[spec[:xero]], spec)
          instance_variable_set("@#{name}", value)
        end
      end

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
