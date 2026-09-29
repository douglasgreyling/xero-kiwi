# frozen_string_literal: true

# Assertions against real recorded Xero responses.
#
# The cassettes these replay have been in the repo since early on, and the
# specs that used them asserted things like:
#
#   expect(result).to all(be_a(Accounting::CreditNote)).or eq([])
#
# which passes when every attribute is nil. Four silent bugs shipped while
# those specs were green, and `credit_notes/list.yml` contained the evidence
# disproving one of them the entire time — 13 `"Amount"` keys, zero
# `"AppliedAmount"`. Nothing read it.
#
# So these assert **values**, not classes, and each one is tied to a
# regression that actually happened. `record: :none` throughout: a cassette
# that stops matching must fail loudly rather than quietly re-record itself
# and start testing the gem against its own output.
# Cuts across several resources on purpose — what binds these is the payload
# being real, not the class under test.
RSpec.describe "recorded Xero responses" do # rubocop:disable RSpec/DescribeClass
  let(:tenant_id) { "22222222-2222-2222-2222-000000000001" }
  let(:client)    { XeroKiwi::Client.new(access_token: "test_token") }

  def raw_client
    XeroKiwi::Client.new(access_token: "test_token", retain_raw: true)
  end

  describe "allocations", vcr: { cassette_name: "credit_notes/list", record: :none } do
    subject(:allocations) { client.credit_notes(tenant_id).flat_map(&:allocations) }

    it "are present in the recording at all" do
      expect(allocations).not_to be_empty
    end

    # The 0.6.0 regression. Xero's JSON sends "Amount"; 0.6.0 remapped the
    # attribute to "AppliedAmount" — a key that appears nowhere in this
    # recording — so every allocation read nil, and importers coerced that
    # to 0.0 and stored it.
    it "expose the allocated value rather than nil" do
      expect(allocations.map(&:amount)).to all(be_truthy)
    end

    it "expose it under both names" do
      expect(allocations.map(&:applied_amount)).to all(be_truthy)
    end

    it "carry the invoice each one was applied to" do
      expect(allocations.map { |a| a.invoice&.invoice_id }).to all(be_truthy)
    end
  end

  # Allocations hang off three resources. The regression would have hit all
  # of them, so all of them are checked against real payloads.
  {
    "overpayments" => :overpayments,
    "prepayments"  => :prepayments
  }.each do |cassette, method|
    describe "#{cassette} allocations", vcr: { cassette_name: "#{cassette}/list", record: :none } do
      it "expose the allocated value rather than nil" do
        amounts = client.public_send(method, tenant_id).flat_map(&:allocations).map(&:amount)

        expect(amounts).to all(be_truthy)
      end
    end
  end

  # Reference was thought absent on prepayments, twice, because the stored
  # XML-era rows a consumer checked had no such key. The recording says
  # otherwise: present on all nine, with real values. Same trap as the
  # allocation bug — XML-derived data answering a question about JSON.
  describe "prepayment references", vcr: { cassette_name: "prepayments/list", record: :none } do
    it "are modelled rather than reachable only through raw" do
      expect(client.prepayments(tenant_id).map(&:reference)).to include(be_truthy)
    end

    # One call, both views — a cassette replays each interaction once, so an
    # example that requests twice fails on the second.
    it "match what the payload carries" do
      prepayments = raw_client.prepayments(tenant_id)

      expect(prepayments.map(&:reference)).to eq(
        prepayments.map { |p| p.raw["Reference"] }.map { |r| r == "" ? nil : r }
      )
    end
  end

  # Found by asymmetry rather than by comparison: Prepayment and Overpayment
  # both modelled `payments` and CreditNote did not, which is visible from
  # the class definitions alone. The recording confirms Xero sends it on
  # every credit note, with data on two of seventeen.
  describe "credit note payments", vcr: { cassette_name: "credit_notes/list", record: :none } do
    it "are modelled, as on the sibling resources" do
      populated = client.credit_notes(tenant_id).map(&:payments).reject(&:empty?)

      expect(populated).not_to be_empty
    end
  end

  # Xero nests *allocation stubs* under an invoice, not whole documents:
  # `AppliedAmount` is what was applied to this invoice, `Total` is the
  # credit note's own total. Modelling the stub as a plain reference left
  # `AppliedAmount` unreachable, so the nearest-looking reader was `total` —
  # a different number on 19 of the 24 stubs in this recording.
  describe "invoice allocation stubs", vcr: { cassette_name: "invoices/list", record: :none } do
    subject(:invoices) { client.invoices(tenant_id) }

    %i[credit_notes prepayments overpayments].each do |association|
      it "expose the amount applied to this invoice, on invoice.#{association}" do
        stubs = invoices.flat_map(&association)

        expect(stubs.map(&:applied_amount)).to all(be_a(BigDecimal))
      end
    end

    it "does not conflate the applied amount with the document total" do
      stubs = invoices.flat_map(&:credit_notes)

      expect(stubs.reject { |s| s.applied_amount == s.total }).not_to be_empty
    end
  end

  # The same attribute on a full document, where Xero sends no such key.
  describe "credit notes fetched in their own right", vcr: { cassette_name: "credit_notes/list", record: :none } do
    it "carry no applied amount, since nothing was applied to anything" do
      expect(client.credit_notes(tenant_id).map(&:applied_amount)).to all(be_nil)
    end
  end

  # Floats cannot represent most decimal fractions, so arithmetic between two
  # money fields drifts while each one still prints correctly. This identity
  # failed on 3 of these 55 invoices before money became BigDecimal.
  describe "money", vcr: { cassette_name: "invoices/list", record: :none } do
    subject(:invoices) do
      client.invoices(tenant_id).reject { |i| i.sub_total.nil? || i.total_tax.nil? || i.total.nil? }
    end

    it "arrives as BigDecimal rather than Float" do
      expect(invoices.map { |i| i.total.class }.uniq).to eq([BigDecimal])
    end

    it "adds up: sub_total + total_tax == total, on every recorded invoice" do
      mismatched = invoices.reject { |i| i.sub_total + i.total_tax == i.total }

      expect(mismatched).to be_empty
    end

    it "holds the decimal Xero wrote, not a binary approximation of it" do
      totals = invoices.map { |i| i.total.to_s("F") }

      expect(totals).to all(match(/\A-?\d+\.\d{1,2}\z/))
    end
  end

  # Each of these is sent on every record in its recording and was reachable
  # only through `raw`. They came out of a comparison against Xero's
  # published OpenAPI spec, which lists all of them — the recordings alone
  # only showed an unread key, not whether Xero meant to send it.
  describe "fields the spec documents and the recordings confirm" do
    it "reads Invoice#is_discounted", vcr: { cassette_name: "invoices/list", record: :none } do
      expect(client.invoices(tenant_id).map(&:is_discounted)).to all(be(false).or(be(true)))
    end

    it "reads CreditNote#has_errors", vcr: { cassette_name: "credit_notes/list", record: :none } do
      expect(client.credit_notes(tenant_id).map(&:has_errors)).to all(be(false).or(be(true)))
    end

    it "reads Contact#has_validation_errors", vcr: { cassette_name: "contacts/list", record: :none } do
      expect(client.contacts(tenant_id).map(&:has_validation_errors)).to all(be(false).or(be(true)))
    end

    it "reads Payment#has_validation_errors", vcr: { cassette_name: "payments/list", record: :none } do
      expect(client.payments(tenant_id).map(&:has_validation_errors)).to all(be(false).or(be(true)))
    end

    it "gives CreditNote#invoice_addresses an array rather than nil", vcr: { cassette_name: "credit_notes/list", record: :none } do
      expect(client.credit_notes(tenant_id).map(&:invoice_addresses)).to all(be_an(Array))
    end
  end

  describe "organisation", vcr: { cassette_name: "organisation/get", record: :none } do
    it "names the kind of tax number it holds" do
      expect(client.organisation(tenant_id).tax_number_name).to eq("VAT Number")
    end
  end

  describe "users", vcr: { cassette_name: "users/list", record: :none } do
    subject(:users) { client.users(tenant_id) }

    it "expose both identifiers" do
      expect(users.map(&:global_user_id)).to all(be_truthy)
    end

    # Keying membership records on the wrong one leaves the association
    # empty with the right count and the right roles.
    it "keeps the two identifiers distinct" do
      expect(users.map { |u| u.user_id == u.global_user_id }).to all(be(false))
    end
  end

  describe "branding themes", vcr: { cassette_name: "branding_themes/list", record: :none } do
    # Xero sends "LogoUrl": "" in this recording. Normalisation had only ever
    # been verified against a fabricated empty string, which is a weaker
    # assertion than it looks — a real one can differ in whitespace, or not
    # be sent at all.
    it "reads Xero's empty LogoUrl as nil" do
      expect(client.branding_themes(tenant_id).map(&:logo_url)).to all(be_nil)
    end

    it "keeps the empty string in raw" do
      theme = raw_client.branding_themes(tenant_id).first

      expect(theme.raw["LogoUrl"]).to eq("")
    end
  end

  describe "rate-limit headers", vcr: { cassette_name: "contacts/list", record: :none } do
    # Every cassette carries Xero's real quota headers, and until now
    # nothing read one. The casing matters: recordings hold
    # X-Daylimit-Remaining, not X-DayLimit-Remaining.
    it "populates the store from a real response", :aggregate_failures do
      c = client
      c.contacts(tenant_id)

      expect(c.rate_limit(tenant_id).known?).to be(true)
      expect(c.rate_limit(tenant_id).reported.day).to be_a(Integer)
    end

    it "reads a plausible daily figure" do
      c = client
      c.contacts(tenant_id)

      expect(c.rate_limit(tenant_id).day_remaining).to be_between(1, 5_000)
    end
  end

  describe "pagination envelope", vcr: { cassette_name: "contacts/paged", record: :none } do
    subject(:page) { client.contacts(tenant_id, page: 1, page_size: 1_000, include_archived: true) }

    # The walker's end-of-walk logic keys off the page size Xero states.
    # Every other cassette predates paging and carries no envelope, so this
    # is the only place a real one is read.
    it "reads the page number Xero stated" do
      expect(page.page).to eq(1)
    end

    it "reads the page size Xero stated" do
      expect(page.reported_page_size).to eq(1_000)
    end

    it "reads the item count Xero stated" do
      expect(page.item_count).to eq(page.size)
    end

    it "carries the contacts themselves" do
      expect(page.map(&:contact_id)).to all(be_truthy)
    end
  end
end
