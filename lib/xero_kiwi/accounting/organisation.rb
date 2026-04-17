# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a Xero Organisation (tenant) returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/organisation
    class Organisation
      include Resource

      identity :organisation_id

      attribute :organisation_id,                xero: "OrganisationID", type: :guid
      attribute :api_key,                        xero: "APIKey"
      attribute :name,                           xero: "Name"
      attribute :legal_name,                     xero: "LegalName"
      attribute :pays_tax,                       xero: "PaysTax", type: :bool
      attribute :version,                        xero: "Version"
      attribute :organisation_type,              xero: "OrganisationType", type: :enum
      attribute :base_currency,                  xero: "BaseCurrency"
      attribute :country_code,                   xero: "CountryCode"
      attribute :is_demo_company,                xero: "IsDemoCompany",                type: :bool
      attribute :organisation_status,            xero: "OrganisationStatus",           type: :enum
      attribute :registration_number,            xero: "RegistrationNumber"
      attribute :employer_identification_number, xero: "EmployerIdentificationNumber"
      attribute :tax_number,                     xero: "TaxNumber"
      attribute :financial_year_end_day,         xero: "FinancialYearEndDay"
      attribute :financial_year_end_month,       xero: "FinancialYearEndMonth"
      attribute :sales_tax_basis,                xero: "SalesTaxBasis"
      attribute :sales_tax_period,               xero: "SalesTaxPeriod"
      attribute :default_sales_tax,              xero: "DefaultSalesTax"
      attribute :default_purchases_tax,          xero: "DefaultPurchasesTax"
      attribute :period_lock_date,               xero: "PeriodLockDate",               type: :date
      attribute :end_of_year_lock_date,          xero: "EndOfYearLockDate",            type: :date
      attribute :created_date_utc,               xero: "CreatedDateUTC",               type: :date
      attribute :timezone,                       xero: "Timezone"
      attribute :organisation_entity_type,       xero: "OrganisationEntityType", type: :enum
      attribute :short_code,                     xero: "ShortCode"
      attribute :organisation_class,             xero: "Class"
      attribute :edition,                        xero: "Edition"
      attribute :line_of_business,               xero: "LineOfBusiness"
      attribute :addresses,                      xero: "Addresses",                    type: :collection, of: Address
      attribute :phones,                         xero: "Phones",                       type: :collection, of: Phone
      attribute :external_links,                 xero: "ExternalLinks",                type: :collection, of: ExternalLink
      attribute :payment_terms,                  xero: "PaymentTerms",                 hydrate: ->(raw) { PaymentTerms.from_hash(raw) }

      # Xero's /Organisation endpoint returns a one-element "Organisations"
      # array — we unwrap it to a single object.
      def self.from_response(payload)
        return nil if payload.nil?

        items = payload["Organisations"]
        return nil if items.nil? || items.empty?

        new(items.first)
      end

      def demo_company? = is_demo_company == true
    end
  end
end
