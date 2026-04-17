# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a contact person nested within a Xero Contact.
    #
    # See: https://developer.xero.com/documentation/api/accounting/contacts
    class ContactPerson
      include Resource

      attribute :first_name,        xero: "FirstName"
      attribute :last_name,         xero: "LastName"
      attribute :email_address,     xero: "EmailAddress"
      attribute :include_in_emails, xero: "IncludeInEmails", type: :bool

      def include_in_emails? = include_in_emails == true
    end
  end
end
