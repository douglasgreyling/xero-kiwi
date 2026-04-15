# frozen_string_literal: true

require "time"

module XeroKiwi
  # Represents a single Xero "Connection" — i.e. a tenant (organisation or
  # practice) that an access token has been authorised against.
  #
  # See: https://developer.xero.com/documentation/guides/oauth2/auth-flow#connections
  class Connection
    ATTRIBUTES = {
      id:               "id",
      auth_event_id:    "authEventId",
      tenant_id:        "tenantId",
      tenant_type:      "tenantType",
      tenant_name:      "tenantName",
      created_date_utc: "createdDateUtc",
      updated_date_utc: "updatedDateUtc"
    }.freeze

    attr_reader(*ATTRIBUTES.keys)

    def self.from_response(payload)
      return [] if payload.nil?

      items = payload.is_a?(Array) ? payload : [payload]
      items.map { |attrs| new(attrs) }
    end

    def initialize(attrs)
      attrs             = attrs.transform_keys(&:to_s)
      @id               = attrs["id"]
      @auth_event_id    = attrs["authEventId"]
      @tenant_id        = attrs["tenantId"]
      @tenant_type      = attrs["tenantType"]
      @tenant_name      = attrs["tenantName"]
      @created_date_utc = parse_time(attrs["createdDateUtc"])
      @updated_date_utc = parse_time(attrs["updatedDateUtc"])
    end

    def organisation? = tenant_type == "ORGANISATION"
    def practice?     = tenant_type == "PRACTICE"

    def to_h
      ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
    end

    def ==(other)
      other.is_a?(Connection) && other.id == id
    end
    alias eql? ==

    def hash = [self.class, id].hash

    def inspect
      "#<#{self.class} id=#{id.inspect} tenant_id=#{tenant_id.inspect} " \
        "tenant_name=#{tenant_name.inspect} tenant_type=#{tenant_type.inspect}>"
    end

    private

    # Xero serialises timestamps in C# DateTime format and frequently omits the
    # timezone marker on values that are documented as UTC (e.g.
    # "2019-07-09T23:40:30.1833130"). Force-append a Z so Time.iso8601 doesn't
    # silently fall back to local time.
    def parse_time(value)
      return nil if value.nil?

      str = value.to_s.strip
      return nil if str.empty?

      str = "#{str}Z" unless str.match?(/[Zz]\z|[+-]\d{2}:?\d{2}\z/)
      Time.iso8601(str)
    rescue ArgumentError
      nil
    end
  end
end
