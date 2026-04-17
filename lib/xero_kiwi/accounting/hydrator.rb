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

      def call(raw, spec) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity
        return spec[:hydrate].call(raw) if spec[:hydrate]
        return [] if spec[:type] == :collection && raw.nil?
        return nil if raw.nil?

        case spec[:type]
        when :string, :enum, :guid, :bool, :decimal
          raw
        when :date
          parse_time(raw)
        when :object
          build_object(raw, spec)
        when :collection
          raw.map { |item| build_object(item, spec) }
        else
          raise ArgumentError, "unknown attribute type: #{spec[:type].inspect}"
        end
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
