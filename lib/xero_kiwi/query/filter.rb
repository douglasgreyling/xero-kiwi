# frozen_string_literal: true

require "date"
require "time"

module XeroKiwi
  module Query
    # Compiles a Ruby-native filter into Xero's `where` expression syntax.
    #
    #   XeroKiwi::Query::Filter.compile(
    #     { status: "AUTHORISED", date: Date.new(2026, 1, 1)..Date.new(2026, 4, 1) },
    #     fields: Invoice.query_fields
    #   )
    #   # => 'Status=="AUTHORISED"&&Date>=DateTime(2026,1,1)&&Date<=DateTime(2026,4,1)'
    #
    # Supported input shapes:
    #
    #   nil                → nil
    #   String             → passthrough (raw escape hatch)
    #   Hash               → walked; each pair becomes `Path==Literal`
    #   Array value        → IN-semantics `(Path==x || Path==y)`
    #   Range value        → `Path>=lo && Path<=hi`
    #   Hash value         → nested `Parent.Child==Literal`, using the child's
    #                        query_fields schema
    #
    # Unknown field keys raise ArgumentError so typos surface immediately.
    module Filter
      module_function

      def compile(where, fields:)
        return nil if where.nil?
        return where if where.is_a?(String)

        raise ArgumentError, "where must be a Hash or String, got #{where.class}" unless where.is_a?(Hash)

        compile_hash(where, fields, nil)
      end

      def compile_hash(hash, fields, prefix)
        hash.map { |key, value| compile_pair(key, value, fields, prefix) }.join("&&")
      end

      def compile_pair(key, value, fields, prefix) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity
        spec = fields.fetch(key) do
          raise ArgumentError, "unknown filter field: #{key.inspect}"
        end

        path = prefix ? "#{prefix}.#{spec[:path]}" : spec[:path]

        case value
        when Array
          "(#{value.map { |v| "#{path}==#{literal(v, spec[:type])}" }.join("||")})"
        when Range
          "#{path}>=#{literal(value.begin, spec[:type])}&&#{path}<=#{literal(value.end, spec[:type])}"
        when Hash
          raise ArgumentError, "#{key.inspect} is not a nested filter field" unless spec[:type] == :nested

          compile_hash(value, spec[:fields], path)
        else
          "#{path}==#{literal(value, spec[:type])}"
        end
      end

      def literal(value, type)
        case type
        when :guid then %(Guid("#{value}"))
        when :string, :enum then quote_string(value)
        when :date         then date_literal(value)
        when :bool         then value ? "true" : "false"
        when :decimal      then value.to_s
        else                    raise ArgumentError, "cannot render #{value.inspect} as #{type.inspect}"
        end
      end

      def quote_string(value)
        escaped = value.to_s.gsub("\\", "\\\\\\\\").gsub('"', '\\"')
        %("#{escaped}")
      end

      # Date → render as-is (a Date IS a day, no timezone shifting).
      # Time → convert to UTC before extracting Y/M/D so `Time.new(..., "+10:00")`
      #        doesn't render the local-timezone day.
      def date_literal(value)
        case value
        when Date then "DateTime(#{value.year},#{value.month},#{value.day})"
        when Time then t = value.utc
                       "DateTime(#{t.year},#{t.month},#{t.day})"
        else           raise ArgumentError, "cannot render #{value.class} as :date"
        end
      end
    end
  end
end
