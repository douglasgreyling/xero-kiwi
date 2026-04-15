# frozen_string_literal: true

require "time"

module XeroKiwi
  module Accounting
    # Represents a Xero Branding Theme returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/brandingthemes
    class BrandingTheme
      ATTRIBUTES = {
        branding_theme_id: "BrandingThemeID",
        name:              "Name",
        logo_url:          "LogoUrl",
        type:              "Type",
        sort_order:        "SortOrder",
        created_date_utc:  "CreatedDateUTC"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def self.from_response(payload)
        return [] if payload.nil?

        items = payload["BrandingThemes"]
        return [] if items.nil?

        items.map { |attrs| new(attrs) }
      end

      def initialize(attrs)
        attrs              = attrs.transform_keys(&:to_s)
        @branding_theme_id = attrs["BrandingThemeID"]
        @name              = attrs["Name"]
        @logo_url          = attrs["LogoUrl"]
        @type              = attrs["Type"]
        @sort_order        = attrs["SortOrder"]
        @created_date_utc  = parse_time(attrs["CreatedDateUTC"])
      end

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(BrandingTheme) && other.branding_theme_id == branding_theme_id
      end
      alias eql? ==

      def hash = [self.class, branding_theme_id].hash

      def inspect
        "#<#{self.class} branding_theme_id=#{branding_theme_id.inspect} " \
          "name=#{name.inspect} type=#{type.inspect}>"
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
