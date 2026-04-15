# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a contact person nested within a Xero Contact.
    #
    # See: https://developer.xero.com/documentation/api/accounting/contacts
    class ContactPerson
      ATTRIBUTES = {
        first_name:        "FirstName",
        last_name:         "LastName",
        email_address:     "EmailAddress",
        include_in_emails: "IncludeInEmails"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def initialize(attrs)
        attrs              = attrs.transform_keys(&:to_s)
        @first_name        = attrs["FirstName"]
        @last_name         = attrs["LastName"]
        @email_address     = attrs["EmailAddress"]
        @include_in_emails = attrs["IncludeInEmails"]
      end

      def include_in_emails? = include_in_emails == true

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(ContactPerson) && to_h == other.to_h
      end
      alias eql? ==

      def hash = to_h.hash

      def inspect
        "#<#{self.class} first_name=#{first_name.inspect} " \
          "last_name=#{last_name.inspect} email_address=#{email_address.inspect}>"
      end
    end
  end
end
