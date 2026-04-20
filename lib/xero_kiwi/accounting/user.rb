# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a Xero User returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/users
    class User
      include Resource

      payload_key "Users"
      identity    :user_id

      attribute :user_id,           xero: "UserID", type: :guid
      attribute :email_address,     xero: "EmailAddress",     query: true
      attribute :first_name,        xero: "FirstName",        query: true
      attribute :last_name,         xero: "LastName",         query: true
      attribute :updated_date_utc,  xero: "UpdatedDateUTC",   type: :date, query: true
      attribute :is_subscriber,     xero: "IsSubscriber",     type: :bool, query: true
      attribute :organisation_role, xero: "OrganisationRole", query: true

      def subscriber? = is_subscriber == true
    end
  end
end
