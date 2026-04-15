# frozen_string_literal: true

require "time"

module XeroKiwi
  module Accounting
    # Represents a Xero Organisation (tenant) returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/organisation
    class Organisation
      ATTRIBUTES = {
        organisation_id:                "OrganisationID",
        api_key:                        "APIKey",
        name:                           "Name",
        legal_name:                     "LegalName",
        pays_tax:                       "PaysTax",
        version:                        "Version",
        organisation_type:              "OrganisationType",
        base_currency:                  "BaseCurrency",
        country_code:                   "CountryCode",
        is_demo_company:                "IsDemoCompany",
        organisation_status:            "OrganisationStatus",
        registration_number:            "RegistrationNumber",
        employer_identification_number: "EmployerIdentificationNumber",
        tax_number:                     "TaxNumber",
        financial_year_end_day:         "FinancialYearEndDay",
        financial_year_end_month:       "FinancialYearEndMonth",
        sales_tax_basis:                "SalesTaxBasis",
        sales_tax_period:               "SalesTaxPeriod",
        default_sales_tax:              "DefaultSalesTax",
        default_purchases_tax:          "DefaultPurchasesTax",
        period_lock_date:               "PeriodLockDate",
        end_of_year_lock_date:          "EndOfYearLockDate",
        created_date_utc:               "CreatedDateUTC",
        timezone:                       "Timezone",
        organisation_entity_type:       "OrganisationEntityType",
        short_code:                     "ShortCode",
        organisation_class:             "Class",
        edition:                        "Edition",
        line_of_business:               "LineOfBusiness",
        addresses:                      "Addresses",
        phones:                         "Phones",
        external_links:                 "ExternalLinks",
        payment_terms:                  "PaymentTerms"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def self.from_response(payload)
        return nil if payload.nil?

        items = payload["Organisations"]
        return nil if items.nil? || items.empty?

        new(items.first)
      end

      def initialize(attrs) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength
        attrs                           = attrs.transform_keys(&:to_s)
        @organisation_id                = attrs["OrganisationID"]
        @api_key                        = attrs["APIKey"]
        @name                           = attrs["Name"]
        @legal_name                     = attrs["LegalName"]
        @pays_tax                       = attrs["PaysTax"]
        @version                        = attrs["Version"]
        @organisation_type              = attrs["OrganisationType"]
        @base_currency                  = attrs["BaseCurrency"]
        @country_code                   = attrs["CountryCode"]
        @is_demo_company                = attrs["IsDemoCompany"]
        @organisation_status            = attrs["OrganisationStatus"]
        @registration_number            = attrs["RegistrationNumber"]
        @employer_identification_number = attrs["EmployerIdentificationNumber"]
        @tax_number                     = attrs["TaxNumber"]
        @financial_year_end_day         = attrs["FinancialYearEndDay"]
        @financial_year_end_month       = attrs["FinancialYearEndMonth"]
        @sales_tax_basis                = attrs["SalesTaxBasis"]
        @sales_tax_period               = attrs["SalesTaxPeriod"]
        @default_sales_tax              = attrs["DefaultSalesTax"]
        @default_purchases_tax          = attrs["DefaultPurchasesTax"]
        @period_lock_date               = parse_time(attrs["PeriodLockDate"])
        @end_of_year_lock_date          = parse_time(attrs["EndOfYearLockDate"])
        @created_date_utc               = parse_time(attrs["CreatedDateUTC"])
        @timezone                       = attrs["Timezone"]
        @organisation_entity_type       = attrs["OrganisationEntityType"]
        @short_code                     = attrs["ShortCode"]
        @organisation_class             = attrs["Class"]
        @edition                        = attrs["Edition"]
        @line_of_business               = attrs["LineOfBusiness"]
        @addresses                      = (attrs["Addresses"] || []).map { |a| Address.new(a) }
        @phones                         = (attrs["Phones"] || []).map { |p| Phone.new(p) }
        @external_links                 = (attrs["ExternalLinks"] || []).map { |l| ExternalLink.new(l) }
        @payment_terms                  = PaymentTerms.from_hash(attrs["PaymentTerms"])
      end

      def demo_company? = is_demo_company == true

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(Organisation) && other.organisation_id == organisation_id
      end
      alias eql? ==

      def hash = [self.class, organisation_id].hash

      def inspect
        "#<#{self.class} organisation_id=#{organisation_id.inspect} " \
          "name=#{name.inspect} organisation_type=#{organisation_type.inspect}>"
      end

      private

      # Xero uses two timestamp formats depending on the endpoint:
      #
      # - ISO 8601: "2019-07-09T23:40:30.1833130" (connections API)
      # - .NET JSON: "/Date(1574275974000)/" (accounting API)
      #
      # Handle both, always returning UTC.
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
