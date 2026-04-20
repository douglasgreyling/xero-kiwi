# frozen_string_literal: true

module XeroKiwi
  module Query
    # Compiles a Ruby-native order spec into Xero's `order` query param.
    #
    #   XeroKiwi::Query::Order.compile(
    #     { date: :desc, invoice_number: :asc },
    #     fields: Invoice.query_fields
    #   )
    #   # => "Date DESC,InvoiceNumber ASC"
    #
    # String input is passed through unchanged (raw escape hatch).
    module Order
      module_function

      def compile(order, fields:)
        return nil if order.nil?
        return order if order.is_a?(String)

        raise ArgumentError, "order must be a Hash or String, got #{order.class}" unless order.is_a?(Hash)

        order.map { |name, direction| clause(name, direction, fields) }.join(",")
      end

      def clause(name, direction, fields)
        spec = fields.fetch(name) do
          raise ArgumentError, "unknown order field: #{name.inspect}"
        end

        "#{spec[:path]} #{direction.to_s.upcase}"
      end
    end
  end
end
