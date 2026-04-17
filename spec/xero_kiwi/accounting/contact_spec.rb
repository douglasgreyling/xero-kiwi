# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::Contact do
  let(:full_attrs) do
    {
      "ContactID"                      => "bd2270c3-8706-4c11-9cfb-000b551c3f51",
      "ContactNumber"                  => "CUST100",
      "AccountNumber"                  => "ABC-100",
      "ContactStatus"                  => "ACTIVE",
      "Name"                           => "ABC Limited",
      "FirstName"                      => "Andrea",
      "LastName"                       => "Dutchess",
      "EmailAddress"                   => "a.dutchess@abclimited.com",
      "BankAccountDetails"             => "45465844",
      "CompanyNumber"                  => "NumberBusiness1234",
      "TaxNumber"                      => "415465456454",
      "TaxNumberType"                  => "ABN",
      "AccountsReceivableTaxType"      => "INPUT2",
      "AccountsPayableTaxType"         => "OUTPUT2",
      "Addresses"                      => [{ "AddressType" => "POBOX" }, { "AddressType" => "STREET" }],
      "Phones"                         => [{ "PhoneType" => "DEFAULT" }, { "PhoneType" => "FAX" }],
      "IsSupplier"                     => false,
      "IsCustomer"                     => true,
      "DefaultCurrency"                => "NZD",
      "UpdatedDateUTC"                 => "/Date(1488391422280+0000)/",
      "ContactPersons"                 => [{ "FirstName" => "John", "LastName" => "Smith",
                                         "EmailAddress" => "john@example.com", "IncludeInEmails" => true }],
      "XeroNetworkKey"                 => "xnk-abc123",
      "MergedToContactID"              => nil,
      "SalesDefaultAccountCode"        => "200",
      "PurchasesDefaultAccountCode"    => "400",
      "SalesTrackingCategories"        => [{ "TrackingCategoryName" => "Region", "TrackingOptionName" => "North" }],
      "PurchasesTrackingCategories"    => [],
      "SalesDefaultLineAmountType"     => "EXCLUSIVE",
      "PurchasesDefaultLineAmountType" => "INCLUSIVE",
      "TrackingCategoryName"           => "Region",
      "TrackingOptionName"             => "North",
      "PaymentTerms"                   => { "Bills" => { "Day" => 15, "Type" => "OFCURRENTMONTH" },
                                            "Sales" => { "Day" => 20, "Type" => "OFFOLLOWINGMONTH" } },
      "ContactGroups"                  => [{ "ContactGroupID" => "grp-1", "Name" => "VIPs" }],
      "Website"                        => "https://www.abclimited.com",
      "BrandingTheme"                  => { "BrandingThemeID" => "theme-1", "Name" => "Standard" },
      "BatchPayments"                  => { "BankAccountNumber" => "12345" },
      "Discount"                       => 10.0,
      "Balances"                       => { "AccountsReceivable" => { "Outstanding" => 100.0 } },
      "HasAttachments"                 => false
    }
  end

  describe ".from_response" do
    it "parses Contacts from the Xero response envelope" do
      payload  = { "Contacts" => [full_attrs] }
      contacts = described_class.from_response(payload)

      expect(contacts).to all(be_a(described_class))
      expect(contacts.first.contact_id).to eq("bd2270c3-8706-4c11-9cfb-000b551c3f51")
    end

    it "returns multiple contacts when present" do
      second  = full_attrs.merge("ContactID" => "abc-123", "Name" => "DEF Limited")
      payload = { "Contacts" => [full_attrs, second] }

      expect(described_class.from_response(payload).size).to eq(2)
    end

    it "returns an empty array when payload is nil" do
      expect(described_class.from_response(nil)).to eq([])
    end

    it "returns an empty array when Contacts key is missing" do
      expect(described_class.from_response({})).to eq([])
    end

    it "returns an empty array when Contacts array is empty" do
      expect(described_class.from_response("Contacts" => [])).to eq([])
    end
  end

  describe "#initialize" do
    subject(:contact) { described_class.new(full_attrs) }

    it "maps all scalar attributes" do
      expect(contact).to have_attributes(
        contact_id:                         "bd2270c3-8706-4c11-9cfb-000b551c3f51",
        contact_number:                     "CUST100",
        account_number:                     "ABC-100",
        contact_status:                     "ACTIVE",
        name:                               "ABC Limited",
        first_name:                         "Andrea",
        last_name:                          "Dutchess",
        email_address:                      "a.dutchess@abclimited.com",
        bank_account_details:               "45465844",
        company_number:                     "NumberBusiness1234",
        tax_number:                         "415465456454",
        tax_number_type:                    "ABN",
        accounts_receivable_tax_type:       "INPUT2",
        accounts_payable_tax_type:          "OUTPUT2",
        is_supplier:                        false,
        is_customer:                        true,
        default_currency:                   "NZD",
        xero_network_key:                   "xnk-abc123",
        sales_default_account_code:         "200",
        purchases_default_account_code:     "400",
        sales_default_line_amount_type:     "EXCLUSIVE",
        purchases_default_line_amount_type: "INCLUSIVE",
        tracking_category_name:             "Region",
        tracking_option_name:               "North",
        website:                            "https://www.abclimited.com",
        discount:                           10.0,
        has_attachments:                    false
      )
    end

    it "parses UpdatedDateUTC in .NET JSON format into a UTC Time" do
      expect(contact.updated_date_utc).to be_a(Time)
      expect(contact.updated_date_utc.utc_offset).to eq(0)
    end

    it "wraps addresses as XeroKiwi::Accounting::Address objects" do
      expect(contact.addresses).to all(be_a(XeroKiwi::Accounting::Address))
      expect(contact.addresses.first.address_type).to eq("POBOX")
    end

    it "wraps phones as XeroKiwi::Accounting::Phone objects" do
      expect(contact.phones).to all(be_a(XeroKiwi::Accounting::Phone))
      expect(contact.phones.first.phone_type).to eq("DEFAULT")
    end

    it "wraps contact_persons as XeroKiwi::Accounting::ContactPerson objects" do
      expect(contact.contact_persons).to all(be_a(XeroKiwi::Accounting::ContactPerson))
      expect(contact.contact_persons.first.first_name).to eq("John")
    end

    it "wraps payment_terms as a XeroKiwi::Accounting::PaymentTerms object" do
      expect(contact.payment_terms).to be_a(XeroKiwi::Accounting::PaymentTerms)
      expect(contact.payment_terms.bills).to have_attributes(day: 15, type: "OFCURRENTMONTH")
    end

    it "wraps contact_groups as XeroKiwi::Accounting::ContactGroup references" do
      expect(contact.contact_groups).to all(be_a(XeroKiwi::Accounting::ContactGroup))
      expect(contact.contact_groups.first.contact_group_id).to eq("grp-1")
      expect(contact.contact_groups.first.reference?).to be true
    end

    it "wraps branding_theme as a XeroKiwi::Accounting::BrandingTheme" do
      expect(contact.branding_theme).to be_a(XeroKiwi::Accounting::BrandingTheme)
      expect(contact.branding_theme.branding_theme_id).to eq("theme-1")
      expect(contact.branding_theme.name).to eq("Standard")
    end

    it "wraps tracking categories as XeroKiwi::Accounting::TrackingCategory objects" do
      expect(contact.sales_tracking_categories).to all(be_a(XeroKiwi::Accounting::TrackingCategory))
      expect(contact.purchases_tracking_categories).to eq([])
    end

    it "preserves raw data for remaining complex nested objects" do
      expect(contact.balances).to eq({ "AccountsReceivable" => { "Outstanding" => 100.0 } })
      expect(contact.batch_payments).to eq({ "BankAccountNumber" => "12345" })
    end

    it "defaults collection attributes to empty arrays when absent" do
      contact = described_class.new({ "ContactID" => "abc" })

      expect(contact).to have_attributes(
        addresses:                     [],
        phones:                        [],
        contact_persons:               [],
        contact_groups:                [],
        sales_tracking_categories:     [],
        purchases_tracking_categories: []
      )
    end

    it "defaults payment_terms to nil when absent" do
      contact = described_class.new({ "ContactID" => "abc" })
      expect(contact.payment_terms).to be_nil
    end
  end

  describe "#reference?" do
    it "returns false by default" do
      contact = described_class.new({ "ContactID" => "abc" })
      expect(contact.reference?).to be false
    end

    it "returns true when constructed with reference: true" do
      contact = described_class.new({ "ContactID" => "abc", "Name" => "Test" }, reference: true)
      expect(contact.reference?).to be true
    end

    it "returns false for contacts from from_response" do
      payload = { "Contacts" => [full_attrs] }
      contact = described_class.from_response(payload).first
      expect(contact.reference?).to be false
    end
  end

  describe "predicates" do
    it "supplier? returns true when IsSupplier is true" do
      contact = described_class.new({ "ContactID" => "abc", "IsSupplier" => true })
      expect(contact.supplier?).to be true
    end

    it "customer? returns true when IsCustomer is true" do
      contact = described_class.new({ "ContactID" => "abc", "IsCustomer" => true })
      expect(contact.customer?).to be true
    end

    it "active? returns true when ContactStatus is ACTIVE" do
      contact = described_class.new({ "ContactID" => "abc", "ContactStatus" => "ACTIVE" })
      expect(contact.active?).to be true
    end

    it "archived? returns true when ContactStatus is ARCHIVED" do
      contact = described_class.new({ "ContactID" => "abc", "ContactStatus" => "ARCHIVED" })
      expect(contact.archived?).to be true
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      contact = described_class.new(full_attrs)
      hash    = contact.to_h

      expect(hash[:contact_id]).to eq("bd2270c3-8706-4c11-9cfb-000b551c3f51")
      expect(hash[:name]).to eq("ABC Limited")
      expect(hash.keys).to match_array(described_class.attributes.keys)
    end
  end

  describe "equality" do
    it "considers two contacts equal when they share the same contact_id" do
      a = described_class.new({ "ContactID" => "abc", "Name" => "A" })
      b = described_class.new({ "ContactID" => "abc", "Name" => "B" })

      expect(a).to eq(b)
      expect(a).to eql(b)
      expect(a.hash).to eq(b.hash)
    end

    it "considers contacts with different IDs unequal" do
      a = described_class.new({ "ContactID" => "abc" })
      b = described_class.new({ "ContactID" => "xyz" })

      expect(a).not_to eq(b)
    end
  end

  describe "#inspect" do
    it "includes the id, name, and status" do
      contact = described_class.new(full_attrs)

      expect(contact.inspect).to include("contact_id=")
      expect(contact.inspect).to include("name=")
      expect(contact.inspect).to include("contact_status=")
    end
  end
end
