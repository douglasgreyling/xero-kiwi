# frozen_string_literal: true

RSpec.describe XeroKiwi::Accounting::Organisation do
  let(:full_payload) do
    {
      "OrganisationID"               => "b2c885a0-e8de-4867-8b68-1442f7e4e162",
      "APIKey"                       => "APIKEY123",
      "Name"                         => "Maple Florists Ltd",
      "LegalName"                    => "Maple Florists Limited",
      "PaysTax"                      => true,
      "Version"                      => "NZ",
      "OrganisationType"             => "COMPANY",
      "BaseCurrency"                 => "NZD",
      "CountryCode"                  => "NZ",
      "IsDemoCompany"                => false,
      "OrganisationStatus"           => "ACTIVE",
      "RegistrationNumber"           => "1234567",
      "EmployerIdentificationNumber" => "EIN-123",
      "TaxNumber"                    => "TAX-456",
      "FinancialYearEndDay"          => 31,
      "FinancialYearEndMonth"        => 3,
      "SalesTaxBasis"                => "Payments",
      "SalesTaxPeriod"               => "TWOMONTHS",
      "DefaultSalesTax"              => "Tax Exclusive",
      "DefaultPurchasesTax"          => "Tax Exclusive",
      "PeriodLockDate"               => "2023-03-31T00:00:00",
      "EndOfYearLockDate"            => "2023-03-31T00:00:00",
      "CreatedDateUTC"               => "2019-07-09T23:40:30.1833130",
      "Timezone"                     => "NEWZEALANDSTANDARDTIME",
      "OrganisationEntityType"       => "COMPANY",
      "ShortCode"                    => "!b2X9q",
      "Class"                        => "PREMIUM",
      "Edition"                      => "BUSINESS",
      "LineOfBusiness"               => "Florist",
      "Addresses"                    => [{ "AddressType" => "STREET" }],
      "Phones"                       => [{ "PhoneType" => "DEFAULT" }],
      "ExternalLinks"                => [{ "LinkType" => "Facebook" }],
      "PaymentTerms"                 => { "Bills" => { "Day" => 15, "Type" => "OFCURRENTMONTH" },
                                          "Sales" => { "Day" => 20, "Type" => "OFFOLLOWINGMONTH" } }
    }
  end

  describe ".from_response" do
    it "parses an Organisation from the Xero response envelope" do
      payload = { "Organisations" => [full_payload] }
      org     = described_class.from_response(payload)

      expect(org).to be_a(described_class)
      expect(org.organisation_id).to eq("b2c885a0-e8de-4867-8b68-1442f7e4e162")
      expect(org.name).to eq("Maple Florists Ltd")
    end

    it "returns nil when payload is nil" do
      expect(described_class.from_response(nil)).to be_nil
    end

    it "returns nil when Organisations key is missing" do
      expect(described_class.from_response({})).to be_nil
    end

    it "returns nil when Organisations array is empty" do
      expect(described_class.from_response("Organisations" => [])).to be_nil
    end
  end

  describe "#initialize" do
    subject(:org) { described_class.new(full_payload) }

    it "maps all scalar attributes" do
      expect(org).to have_attributes(
        organisation_id:                "b2c885a0-e8de-4867-8b68-1442f7e4e162",
        api_key:                        "APIKEY123",
        name:                           "Maple Florists Ltd",
        legal_name:                     "Maple Florists Limited",
        pays_tax:                       true,
        version:                        "NZ",
        organisation_type:              "COMPANY",
        base_currency:                  "NZD",
        country_code:                   "NZ",
        is_demo_company:                false,
        organisation_status:            "ACTIVE",
        registration_number:            "1234567",
        employer_identification_number: "EIN-123",
        tax_number:                     "TAX-456",
        financial_year_end_day:         31,
        financial_year_end_month:       3,
        sales_tax_basis:                "Payments",
        sales_tax_period:               "TWOMONTHS",
        default_sales_tax:              "Tax Exclusive",
        default_purchases_tax:          "Tax Exclusive",
        timezone:                       "NEWZEALANDSTANDARDTIME",
        organisation_entity_type:       "COMPANY",
        short_code:                     "!b2X9q",
        organisation_class:             "PREMIUM",
        edition:                        "BUSINESS",
        line_of_business:               "Florist"
      )
    end

    it "parses time fields into UTC Time objects" do
      expect(org.created_date_utc).to be_a(Time)
      expect(org.created_date_utc.utc_offset).to eq(0)
      expect(org.period_lock_date).to be_a(Time)
      expect(org.end_of_year_lock_date).to be_a(Time)
    end

    it "wraps addresses as XeroKiwi::Accounting::Address objects" do
      expect(org.addresses).to all(be_a(XeroKiwi::Accounting::Address))
      expect(org.addresses.first.address_type).to eq("STREET")
    end

    it "wraps phones as XeroKiwi::Accounting::Phone objects" do
      expect(org.phones).to all(be_a(XeroKiwi::Accounting::Phone))
      expect(org.phones.first.phone_type).to eq("DEFAULT")
    end

    it "wraps external_links as XeroKiwi::Accounting::ExternalLink objects" do
      expect(org.external_links).to all(be_a(XeroKiwi::Accounting::ExternalLink))
      expect(org.external_links.first.link_type).to eq("Facebook")
    end

    it "wraps payment_terms as a XeroKiwi::Accounting::PaymentTerms object" do
      expect(org.payment_terms).to be_a(XeroKiwi::Accounting::PaymentTerms)
      expect(org.payment_terms.bills).to have_attributes(day: 15, type: "OFCURRENTMONTH")
      expect(org.payment_terms.sales).to have_attributes(day: 20, type: "OFFOLLOWINGMONTH")
    end

    it "defaults collection attributes to empty arrays when absent" do
      org = described_class.new("OrganisationID" => "abc")
      expect(org.addresses).to eq([])
      expect(org.phones).to eq([])
      expect(org.external_links).to eq([])
    end

    it "defaults payment_terms to nil when absent" do
      org = described_class.new("OrganisationID" => "abc")
      expect(org.payment_terms).to be_nil
    end
  end

  describe "#demo_company?" do
    it "returns true when IsDemoCompany is true" do
      org = described_class.new(full_payload.merge("IsDemoCompany" => true))
      expect(org.demo_company?).to be true
    end

    it "returns false when IsDemoCompany is false" do
      org = described_class.new(full_payload.merge("IsDemoCompany" => false))
      expect(org.demo_company?).to be false
    end
  end

  describe "#to_h" do
    it "returns a hash keyed by ruby attribute names" do
      org  = described_class.new(full_payload)
      hash = org.to_h

      expect(hash[:organisation_id]).to eq("b2c885a0-e8de-4867-8b68-1442f7e4e162")
      expect(hash[:name]).to eq("Maple Florists Ltd")
      expect(hash.keys).to match_array(described_class::ATTRIBUTES.keys)
    end
  end

  describe "equality" do
    it "considers two organisations equal when they share the same organisation_id" do
      a = described_class.new("OrganisationID" => "abc", "Name" => "A")
      b = described_class.new("OrganisationID" => "abc", "Name" => "B")

      expect(a).to eq(b)
      expect(a).to eql(b)
      expect(a.hash).to eq(b.hash)
    end

    it "considers organisations with different IDs unequal" do
      a = described_class.new("OrganisationID" => "abc")
      b = described_class.new("OrganisationID" => "xyz")

      expect(a).not_to eq(b)
    end
  end

  describe "#inspect" do
    it "includes the id, name, and type" do
      org = described_class.new(full_payload)
      expect(org.inspect).to include("organisation_id=")
      expect(org.inspect).to include("name=")
      expect(org.inspect).to include("organisation_type=")
    end
  end
end
