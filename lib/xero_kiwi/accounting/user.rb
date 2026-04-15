# frozen_string_literal: true

require "time"

module XeroKiwi
  module Accounting
    # Represents a Xero User returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/users
    class User
      ATTRIBUTES = {
        user_id:           "UserID",
        email_address:     "EmailAddress",
        first_name:        "FirstName",
        last_name:         "LastName",
        updated_date_utc:  "UpdatedDateUTC",
        is_subscriber:     "IsSubscriber",
        organisation_role: "OrganisationRole"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def self.from_response(payload)
        return [] if payload.nil?

        items = payload["Users"]
        return [] if items.nil?

        items.map { |attrs| new(attrs) }
      end

      def initialize(attrs)
        attrs              = attrs.transform_keys(&:to_s)
        @user_id           = attrs["UserID"]
        @email_address     = attrs["EmailAddress"]
        @first_name        = attrs["FirstName"]
        @last_name         = attrs["LastName"]
        @updated_date_utc  = parse_time(attrs["UpdatedDateUTC"])
        @is_subscriber     = attrs["IsSubscriber"]
        @organisation_role = attrs["OrganisationRole"]
      end

      def subscriber? = is_subscriber == true

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(User) && other.user_id == user_id
      end
      alias eql? ==

      def hash = [self.class, user_id].hash

      def inspect
        "#<#{self.class} user_id=#{user_id.inspect} " \
          "email_address=#{email_address.inspect} organisation_role=#{organisation_role.inspect}>"
      end

      private

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
    end
  end
end
