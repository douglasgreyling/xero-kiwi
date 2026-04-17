# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a Xero Contact Group returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/contactgroups
    class ContactGroup
      include Resource

      payload_key "ContactGroups"
      identity    :contact_group_id

      attribute :contact_group_id, xero: "ContactGroupID", type: :guid
      attribute :name,             xero: "Name"
      attribute :status,           xero: "Status"
      attribute :contacts,         xero: "Contacts", type: :collection, of: Contact, reference: true

      def active? = status == "ACTIVE"
    end
  end
end
