# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # Represents a Xero Contact returned by the Accounting API.
    #
    # See: https://developer.xero.com/documentation/api/accounting/contacts
    class Contact
      include Resource

      payload_key "Contacts"
      identity    :contact_id

      # Some classes referenced below (TrackingCategory, ContactGroup,
      # BrandingTheme) haven't been loaded at the time Contact's class body
      # runs, so the lookup is deferred with a String reference.

      attribute :contact_id,                         xero: "ContactID", type: :guid
      attribute :contact_number,                     xero: "ContactNumber"
      attribute :account_number,                     xero: "AccountNumber"
      attribute :contact_status,                     xero: "ContactStatus", type: :enum
      attribute :name,                               xero: "Name"
      attribute :first_name,                         xero: "FirstName"
      attribute :last_name,                          xero: "LastName"
      attribute :email_address,                      xero: "EmailAddress"
      attribute :bank_account_details,               xero: "BankAccountDetails"
      attribute :company_number,                     xero: "CompanyNumber"
      attribute :tax_number,                         xero: "TaxNumber"
      attribute :tax_number_type,                    xero: "TaxNumberType"
      attribute :accounts_receivable_tax_type,       xero: "AccountsReceivableTaxType"
      attribute :accounts_payable_tax_type,          xero: "AccountsPayableTaxType"
      attribute :addresses,                          xero: "Addresses",                      type: :collection, of: Address
      attribute :phones,                             xero: "Phones",                         type: :collection, of: Phone
      attribute :is_supplier,                        xero: "IsSupplier",                     type: :bool
      attribute :is_customer,                        xero: "IsCustomer",                     type: :bool
      attribute :default_currency,                   xero: "DefaultCurrency"
      attribute :updated_date_utc,                   xero: "UpdatedDateUTC",                 type: :date
      attribute :contact_persons,                    xero: "ContactPersons",                 type: :collection, of: ContactPerson
      attribute :xero_network_key,                   xero: "XeroNetworkKey"
      attribute :merged_to_contact_id,               xero: "MergedToContactID", type: :guid
      attribute :sales_default_account_code,         xero: "SalesDefaultAccountCode"
      attribute :purchases_default_account_code,     xero: "PurchasesDefaultAccountCode"
      attribute :sales_tracking_categories,          xero: "SalesTrackingCategories",        type: :collection, of: "TrackingCategory"
      attribute :purchases_tracking_categories,      xero: "PurchasesTrackingCategories",    type: :collection, of: "TrackingCategory"
      attribute :sales_default_line_amount_type,     xero: "SalesDefaultLineAmountType"
      attribute :purchases_default_line_amount_type, xero: "PurchasesDefaultLineAmountType"
      attribute :tracking_category_name,             xero: "TrackingCategoryName"
      attribute :tracking_option_name,               xero: "TrackingOptionName"
      attribute :payment_terms,                      xero: "PaymentTerms",                   hydrate: ->(raw) { PaymentTerms.from_hash(raw) }
      attribute :contact_groups,                     xero: "ContactGroups",                  type: :collection, of: "ContactGroup", reference: true
      attribute :website,                            xero: "Website"
      attribute :branding_theme,                     xero: "BrandingTheme", type: :object, of: "BrandingTheme"
      attribute :batch_payments,                     xero: "BatchPayments"
      attribute :discount,                           xero: "Discount"
      attribute :balances,                           xero: "Balances"
      attribute :has_attachments,                    xero: "HasAttachments", type: :bool

      def supplier? = is_supplier == true

      def customer? = is_customer == true

      def active? = contact_status == "ACTIVE"

      def archived? = contact_status == "ARCHIVED"
    end
  end
end
