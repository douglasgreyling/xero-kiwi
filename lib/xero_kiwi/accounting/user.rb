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

      # Xero returns two distinct identifiers. UserID is scoped to the
      # organisation; GlobalUserID identifies the person across every
      # organisation they belong to, and is what an OIDC id_token subject
      # corresponds to. They differ for every user — key membership records
      # on the one your own user table uses.
      attribute :user_id,           xero: "UserID",           type: :guid
      attribute :global_user_id,    xero: "GlobalUserID",     type: :guid
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
