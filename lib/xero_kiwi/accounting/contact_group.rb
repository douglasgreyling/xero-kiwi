# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a Xero Contact Group returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/contactgroups
    class ContactGroup
      ATTRIBUTES = {
        contact_group_id: "ContactGroupID",
        name:             "Name",
        status:           "Status",
        contacts:         "Contacts"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def self.from_response(payload)
        return [] if payload.nil?

        items = payload["ContactGroups"]
        return [] if items.nil?

        items.map { |attrs| new(attrs) }
      end

      def initialize(attrs, reference: false)
        attrs             = attrs.transform_keys(&:to_s)
        @is_reference     = reference
        @contact_group_id = attrs["ContactGroupID"]
        @name             = attrs["Name"]
        @status           = attrs["Status"]
        @contacts         = (attrs["Contacts"] || []).map { |c| Contact.new(c, reference: true) }
      end

      def reference? = @is_reference

      def active? = status == "ACTIVE"

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(ContactGroup) && other.contact_group_id == contact_group_id
      end
      alias eql? ==

      def hash = [self.class, contact_group_id].hash

      def inspect
        "#<#{self.class} contact_group_id=#{contact_group_id.inspect} " \
          "name=#{name.inspect} status=#{status.inspect}>"
      end
    end
  end
end
