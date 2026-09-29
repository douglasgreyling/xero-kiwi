# frozen_string_literal: true

require "time"

module XeroKiwi
  module Accounting
    # Hydrates a raw JSON value into a typed Ruby attribute, driven by the
    # metadata declared via the Resource DSL (see resource.rb).
    #
    # Supported types:
    #
    #   :string / :enum / :guid / :bool / :decimal  - pass-through
    #   :date                                       - parsed to a UTC Time
    #   :object                                     - Klass.new(raw[, reference: true])
    #   :collection                                 - Array of Klass.new(item[, reference: true])
    #
    # A custom `hydrate: ->(raw) { ... }` lambda short-circuits dispatch and
    # runs before the nil guard, so it can return a value for nil/empty raw
    # input (e.g. PaymentTerms's nil-and-empty-hash handling).
    module Hydrator
      module_function

      def call(raw, spec)
        return spec[:hydrate].call(raw) if spec[:hydrate]
        return [] if spec[:type] == :collection && raw.nil?
        return nil if raw.nil?

        hydrate_typed(raw, spec)
      end

      def hydrate_typed(raw, spec)
        case spec[:type]
        when :string, :enum, :guid then blank_to_nil(raw)
        when :bool, :decimal       then raw
        when :date                 then parse_time(raw)
        when :object               then build_object(raw, spec)
        when :collection           then raw.map { |item| build_object(item, spec) }
        else raise ArgumentError, "unknown attribute type: #{spec[:type].inspect}"
        end
      end

      # Xero sends "" for a text field that has no value, where its XML
      # representation produced nil. Left alone, that empty string reaches a
      # database column and quietly changes what queries match — a
      # `where.not(logo_url: nil)` starts returning rows with no logo.
      #
      # Only exactly "" becomes nil. Whitespace is left alone: " " may be
      # deliberate, and trimming it would be editorialising on a value
      # rather than recognising an absent one. `raw` is untouched either
      # way, so the original payload is always recoverable.
      #
      # `:date` has always done this (see parse_time); strings behaving
      # differently was an inconsistency, not a principle.
      def blank_to_nil(value)
        value == "" ? nil : value
      end

      # Xero uses two timestamp formats depending on the endpoint:
      #
      #   ISO 8601:  "2019-07-09T23:40:30.1833130" (connections API)
      #   .NET JSON: "/Date(1574275974000)/"       (accounting API)
      #
      # Both parse to UTC Time. Unparseable input returns nil.
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

      def build_object(raw, spec)
        target = spec[:of] or raise ArgumentError, "#{spec[:type].inspect} attribute requires `of:`"

        klass = target.is_a?(Class) ? target : resolve_class(target)

        if spec[:reference]
          klass.new(raw, reference: true)
        else
          klass.new(raw)
        end
      end

      # `of:` accepts a String/Symbol to defer constant lookup — useful when a
      # resource references another that hasn't been loaded yet (forward refs).
      def resolve_class(name)
        name.to_s.split("::").reduce(XeroKiwi::Accounting) do |namespace, part|
          namespace.const_get(part)
        end
      end
    end
  end
end
