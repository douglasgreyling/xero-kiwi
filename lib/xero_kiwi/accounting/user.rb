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
      attribute :email_address,     xero: "EmailAddress"
      attribute :first_name,        xero: "FirstName"
      attribute :last_name,         xero: "LastName"
      attribute :updated_date_utc,  xero: "UpdatedDateUTC",   type: :date
      attribute :is_subscriber,     xero: "IsSubscriber",     type: :bool
      attribute :organisation_role, xero: "OrganisationRole"

      def subscriber? = is_subscriber == true
    end
  end
end
