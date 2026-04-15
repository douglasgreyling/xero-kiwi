# frozen_string_literal: true

require "time"

module XeroKiwi
  module Accounting
    # Represents a Xero Contact returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/contacts
    class Contact
      ATTRIBUTES = {
        contact_id:                         "ContactID",
        contact_number:                     "ContactNumber",
        account_number:                     "AccountNumber",
        contact_status:                     "ContactStatus",
        name:                               "Name",
        first_name:                         "FirstName",
        last_name:                          "LastName",
        email_address:                      "EmailAddress",
        bank_account_details:               "BankAccountDetails",
        company_number:                     "CompanyNumber",
        tax_number:                         "TaxNumber",
        tax_number_type:                    "TaxNumberType",
        accounts_receivable_tax_type:       "AccountsReceivableTaxType",
        accounts_payable_tax_type:          "AccountsPayableTaxType",
        addresses:                          "Addresses",
        phones:                             "Phones",
        is_supplier:                        "IsSupplier",
        is_customer:                        "IsCustomer",
        default_currency:                   "DefaultCurrency",
        updated_date_utc:                   "UpdatedDateUTC",
        contact_persons:                    "ContactPersons",
        xero_network_key:                   "XeroNetworkKey",
        merged_to_contact_id:               "MergedToContactID",
        sales_default_account_code:         "SalesDefaultAccountCode",
        purchases_default_account_code:     "PurchasesDefaultAccountCode",
        sales_tracking_categories:          "SalesTrackingCategories",
        purchases_tracking_categories:      "PurchasesTrackingCategories",
        sales_default_line_amount_type:     "SalesDefaultLineAmountType",
        purchases_default_line_amount_type: "PurchasesDefaultLineAmountType",
        tracking_category_name:             "TrackingCategoryName",
        tracking_option_name:               "TrackingOptionName",
        payment_terms:                      "PaymentTerms",
        contact_groups:                     "ContactGroups",
        website:                            "Website",
        branding_theme:                     "BrandingTheme",
        batch_payments:                     "BatchPayments",
        discount:                           "Discount",
        balances:                           "Balances",
        has_attachments:                    "HasAttachments"
      }.freeze

      attr_reader(*ATTRIBUTES.keys)

      def self.from_response(payload)
        return [] if payload.nil?

        items = payload["Contacts"]
        return [] if items.nil?

        items.map { |attrs| new(attrs) }
      end

      def initialize(attrs, reference: false) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
        attrs                               = attrs.transform_keys(&:to_s)
        @is_reference                       = reference
        @contact_id                         = attrs["ContactID"]
        @contact_number                     = attrs["ContactNumber"]
        @account_number                     = attrs["AccountNumber"]
        @contact_status                     = attrs["ContactStatus"]
        @name                               = attrs["Name"]
        @first_name                         = attrs["FirstName"]
        @last_name                          = attrs["LastName"]
        @email_address                      = attrs["EmailAddress"]
        @bank_account_details               = attrs["BankAccountDetails"]
        @company_number                     = attrs["CompanyNumber"]
        @tax_number                         = attrs["TaxNumber"]
        @tax_number_type                    = attrs["TaxNumberType"]
        @accounts_receivable_tax_type       = attrs["AccountsReceivableTaxType"]
        @accounts_payable_tax_type          = attrs["AccountsPayableTaxType"]
        @addresses                          = (attrs["Addresses"] || []).map { |a| Address.new(a) }
        @phones                             = (attrs["Phones"] || []).map { |p| Phone.new(p) }
        @is_supplier                        = attrs["IsSupplier"]
        @is_customer                        = attrs["IsCustomer"]
        @default_currency                   = attrs["DefaultCurrency"]
        @updated_date_utc                   = parse_time(attrs["UpdatedDateUTC"])
        @contact_persons                    = (attrs["ContactPersons"] || []).map { |cp| ContactPerson.new(cp) }
        @xero_network_key                   = attrs["XeroNetworkKey"]
        @merged_to_contact_id               = attrs["MergedToContactID"]
        @sales_default_account_code         = attrs["SalesDefaultAccountCode"]
        @purchases_default_account_code     = attrs["PurchasesDefaultAccountCode"]
        @sales_tracking_categories          = (attrs["SalesTrackingCategories"] || []).map { |t| TrackingCategory.new(t) }
        @purchases_tracking_categories      = (attrs["PurchasesTrackingCategories"] || []).map { |t| TrackingCategory.new(t) }
        @sales_default_line_amount_type     = attrs["SalesDefaultLineAmountType"]
        @purchases_default_line_amount_type = attrs["PurchasesDefaultLineAmountType"]
        @tracking_category_name             = attrs["TrackingCategoryName"]
        @tracking_option_name               = attrs["TrackingOptionName"]
        @payment_terms                      = PaymentTerms.from_hash(attrs["PaymentTerms"])
        @contact_groups                     = (attrs["ContactGroups"] || []).map { |cg| ContactGroup.new(cg, reference: true) }
        @website                            = attrs["Website"]
        @branding_theme                     = attrs["BrandingTheme"] ? BrandingTheme.new(attrs["BrandingTheme"]) : nil
        @batch_payments                     = attrs["BatchPayments"]
        @discount                           = attrs["Discount"]
        @balances                           = attrs["Balances"]
        @has_attachments                    = attrs["HasAttachments"]
      end

      def reference? = @is_reference

      def supplier? = is_supplier == true

      def customer? = is_customer == true

      def active? = contact_status == "ACTIVE"

      def archived? = contact_status == "ARCHIVED"

      def to_h
        ATTRIBUTES.keys.to_h { |key| [key, public_send(key)] }
      end

      def ==(other)
        other.is_a?(Contact) && other.contact_id == contact_id
      end
      alias eql? ==

      def hash = [self.class, contact_id].hash

      def inspect
        "#<#{self.class} contact_id=#{contact_id.inspect} " \
          "name=#{name.inspect} contact_status=#{contact_status.inspect}>"
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
