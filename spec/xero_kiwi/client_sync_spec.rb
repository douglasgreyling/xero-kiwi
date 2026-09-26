# frozen_string_literal: true

# Covers the 0.5.0 sync-support surface: page sizing, archived contacts, raw
# payload retention, page-level iteration with start_page, and rate-limit
# introspection. Kept apart from client_spec.rb, which is already long and
# organised one describe per endpoint.
RSpec.describe XeroKiwi::Client do
  let(:access_token)      { "test_token" }
  let(:tenant_id)         { "70784a63-d24b-46a9-a4db-0e70a274b056" }
  let(:json_headers)      { { "Content-Type" => "application/json" } }
  let(:invoices_endpoint) { "https://api.xero.com/api.xro/2.0/Invoices" }
  let(:contacts_endpoint) { "https://api.xero.com/api.xro/2.0/Contacts" }

  def client(**)
    described_class.new(access_token: access_token, **)
  end

  def stub_invoice_page(number, ids, page_size: nil)
    body = page_size ? invoice_body(ids, page: number, page_size: page_size) : invoice_body(ids)

    stub_request(:get, invoices_endpoint)
      .with(query: hash_including("page" => number.to_s))
      .to_return(status: 200, body: JSON.dump(body), headers: json_headers)
  end

  # A limiter implementing both halves of the contract, without leaking a
  # constant into the example group. Real bucket behaviour is covered against
  # a live Redis in redis_token_bucket_spec.
  def stub_limiter(minute:, day:)
    counts = { minute: minute, day: day }

    Object.new.tap do |limiter|
      limiter.define_singleton_method(:acquire) { |_key| nil }
      limiter.define_singleton_method(:remaining) { |_key| counts }
    end
  end

  # `pagination` present means Xero stated its own page size; absent is the
  # case the walker has to infer from what it received.
  def invoice_body(ids, page: nil, page_size: nil)
    body = { "Invoices" => ids.map { |id| { "InvoiceID" => id } } }
    return body if page.nil?

    body.merge("pagination" => { "page" => page, "pageSize" => page_size, "pageCount" => 9, "itemCount" => 99 })
  end

  describe "page_size" do
    it "omits the pageSize param when neither a default nor an override is set" do
      stub_request(:get, invoices_endpoint)
        .to_return(status: 200, body: JSON.dump(invoice_body(%w[a])), headers: json_headers)

      client.invoices(tenant_id)

      expect(WebMock).to have_requested(:get, invoices_endpoint)
        .with { |req| !req.uri.query.to_s.include?("pageSize") }
    end

    it "applies the client-level default" do
      stub = stub_request(:get, invoices_endpoint)
             .with(query: { "pageSize" => "1000" })
             .to_return(status: 200, body: JSON.dump(invoice_body(%w[a])), headers: json_headers)

      client(page_size: 1000).invoices(tenant_id)

      expect(stub).to have_been_requested
    end

    it "lets a per-call override win over the client default" do
      stub = stub_request(:get, invoices_endpoint)
             .with(query: { "pageSize" => "25" })
             .to_return(status: 200, body: JSON.dump(invoice_body(%w[a])), headers: json_headers)

      client(page_size: 1000).invoices(tenant_id, page_size: 25)

      expect(stub).to have_been_requested
    end

    # Without this, `invoices(page_size: 1000)` would page at 1000 while
    # `each_invoice` still paged at Xero's default — a difference nobody
    # would expect and nothing else would catch.
    it "threads the page size through each_* walks" do
      stub = stub_request(:get, invoices_endpoint)
             .with(query: { "pageSize" => "2", "page" => "1" })
             .to_return(status: 200, body: JSON.dump(invoice_body(%w[a], page: 1, page_size: 2)), headers: json_headers)

      client.each_invoice(tenant_id, page_size: 2).to_a

      expect(stub).to have_been_requested
    end
  end

  describe "walk termination" do
    # Pages of 2 then 1, with an empty page 3 available but not expected.
    def stub_short_walk
      stub_invoice_page(1, %w[a b])
      stub_invoice_page(2, %w[c])
      stub_invoice_page(3, [])
    end

    it "yields every item up to the short page" do
      stub_short_walk

      expect(client.each_invoice(tenant_id).map(&:invoice_id)).to eq(%w[a b c])
    end

    it "does not fetch the page after a short one" do
      stub_short_walk

      client.each_invoice(tenant_id).to_a

      expect(a_request(:get, invoices_endpoint).with(query: hash_including("page" => "3"))).not_to have_been_made
    end

    # The dangerous case. Xero clamps a request above an endpoint's maximum,
    # so measuring "short" against what we *asked for* would end the walk on
    # page 1 and silently truncate the sync.
    it "runs to completion when Xero clamps the requested page size" do
      stub_request(:get, invoices_endpoint).with(query: hash_including("page" => "1"))
                                           .to_return(status: 200, body: JSON.dump(invoice_body(%w[a b])), headers: json_headers)
      stub_request(:get, invoices_endpoint).with(query: hash_including("page" => "2"))
                                           .to_return(status: 200, body: JSON.dump(invoice_body(%w[c d])), headers: json_headers)
      stub_request(:get, invoices_endpoint).with(query: hash_including("page" => "3"))
                                           .to_return(status: 200, body: JSON.dump(invoice_body(%w[e])), headers: json_headers)

      ids = client.each_invoice(tenant_id, page_size: 1000).map(&:invoice_id)

      expect(ids).to eq(%w[a b c d e])
    end

    it "trusts Xero's stated page size when the response carries a pagination envelope" do
      stub_request(:get, invoices_endpoint).with(query: hash_including("page" => "1"))
                                           .to_return(status: 200, body: JSON.dump(invoice_body(%w[a], page: 1, page_size: 5)), headers: json_headers)
      later = stub_request(:get, invoices_endpoint).with(query: hash_including("page" => "2"))
                                                   .to_return(status: 200, body: JSON.dump(invoice_body([])), headers: json_headers)

      client.each_invoice(tenant_id).to_a

      expect(later).not_to have_been_requested
    end
  end

  describe "#each_invoice_page" do
    before do
      stub_request(:get, invoices_endpoint).with(query: hash_including("page" => "3"))
                                           .to_return(status: 200, body: JSON.dump(invoice_body(%w[a b], page: 3, page_size: 2)), headers: json_headers)
      stub_request(:get, invoices_endpoint).with(query: hash_including("page" => "4"))
                                           .to_return(status: 200, body: JSON.dump(invoice_body(%w[c], page: 4, page_size: 2)), headers: json_headers)
    end

    it "starts at start_page rather than page 1" do
      pages = client.each_invoice_page(tenant_id, start_page: 3).map(&:page)

      expect(pages).to eq([3, 4])
    end

    it "yields XeroKiwi::Page objects carrying their items" do
      first = client.each_invoice_page(tenant_id, start_page: 3).first

      expect(first.map(&:invoice_id)).to eq(%w[a b])
    end

    it "returns an Enumerator when no block is given" do
      expect(client.each_invoice_page(tenant_id, start_page: 3)).to be_a(Enumerator)
    end

    it "resumes item iteration from start_page too" do
      ids = client.each_invoice(tenant_id, start_page: 3).map(&:invoice_id)

      expect(ids).to eq(%w[a b c])
    end
  end

  describe "include_archived" do
    it "sends includeArchived on contacts" do
      stub = stub_request(:get, contacts_endpoint)
             .with(query: { "includeArchived" => "true" })
             .to_return(status: 200, body: JSON.dump("Contacts" => []), headers: json_headers)

      client.contacts(tenant_id, include_archived: true)

      expect(stub).to have_been_requested
    end

    it "omits it when not asked for" do
      stub_request(:get, contacts_endpoint)
        .to_return(status: 200, body: JSON.dump("Contacts" => []), headers: json_headers)

      client.contacts(tenant_id)

      expect(WebMock).to have_requested(:get, contacts_endpoint)
        .with { |req| !req.uri.query.to_s.include?("includeArchived") }
    end

    # It's a contacts-only query parameter, not a shared one — the generic
    # list path must not grow it for the other nine resources.
    it "is not accepted on other resources" do
      expect { client.invoices(tenant_id, include_archived: true) }
        .to raise_error(ArgumentError, /unknown keyword: :include_archived/)
    end
  end

  describe "retain_raw" do
    let(:payload) do
      {
        "Contacts" => [
          {
            "ContactID"      => "c1",
            "Name"           => "Maple Florists",
            "ContactPersons" => [{ "FirstName" => "Ada", "LastName" => "Lovelace" }],
            "SomethingNew"   => "a field the gem does not model"
          }
        ]
      }
    end

    before do
      stub_request(:get, contacts_endpoint).to_return(status: 200, body: JSON.dump(payload), headers: json_headers)
    end

    it "is nil by default" do
      expect(client.contacts(tenant_id).first.raw).to be_nil
    end

    it "returns Xero's hash verbatim when opted in" do
      contact = client(retain_raw: true).contacts(tenant_id).first

      expect(contact.raw).to eq(payload["Contacts"].first)
    end

    it "preserves fields the gem does not model" do
      contact = client(retain_raw: true).contacts(tenant_id).first

      expect(contact.raw["SomethingNew"]).to eq("a field the gem does not model")
    end

    it "keeps nested payloads reachable from the top-level hash" do
      contact = client(retain_raw: true).contacts(tenant_id).first

      expect(contact.raw["ContactPersons"]).to eq([{ "FirstName" => "Ada", "LastName" => "Lovelace" }])
    end

    it "is frozen so a caller can't mutate what Xero sent" do
      contact = client(retain_raw: true).contacts(tenant_id).first

      expect(contact.raw).to be_frozen
    end

    # to_h is a snake_case projection rebuilt from the modelled attributes.
    # Storing it where a caller meant to store the payload changes both the
    # keys and the nesting, and every reader then fails by returning nil.
    it "is not the same thing as to_h" do
      contact = client(retain_raw: true).contacts(tenant_id).first

      expect(contact.raw.keys).not_to include(:contact_id)
    end
  end

  describe "#rate_limit" do
    let(:quota_headers) do
      json_headers.merge(
        "X-DayLimit-Remaining"    => "3000",
        "X-MinLimit-Remaining"    => "42",
        "X-AppMinLimit-Remaining" => "900"
      )
    end

    it "is empty before any request has been made" do
      expect(client.rate_limit(tenant_id).known?).to be(false)
    end

    it "captures the figures Xero reported on the last call" do
      stub_request(:get, invoices_endpoint)
        .to_return(status: 200, body: JSON.dump(invoice_body(%w[a])), headers: quota_headers)

      c = client
      c.invoices(tenant_id)

      expect(c.rate_limit(tenant_id)).to have_attributes(day_remaining: 3_000, minute_remaining: 42)
    end

    it "keeps tenants apart" do
      stub_request(:get, invoices_endpoint)
        .to_return(status: 200, body: JSON.dump(invoice_body(%w[a])), headers: quota_headers)

      c = client
      c.invoices(tenant_id)

      expect(c.rate_limit("some-other-tenant").known?).to be(false)
    end

    # A 429 is exactly when the headers matter, so they have to be read
    # before ResponseHandler turns the response into an exception.
    it "still records the figures when the call fails" do
      stub_request(:get, invoices_endpoint)
        .to_return(status: 400, body: "{}", headers: quota_headers)

      c = client
      expect { c.invoices(tenant_id) }.to raise_error(XeroKiwi::ClientError)
      expect(c.rate_limit(tenant_id).day_remaining).to eq(3_000)
    end

    it "blends in the throttle bucket and reports the stricter figure" do
      stub_request(:get, invoices_endpoint)
        .to_return(status: 200, body: JSON.dump(invoice_body(%w[a])), headers: quota_headers)

      c = client(throttle: stub_limiter(minute: 55, day: 500))
      c.invoices(tenant_id)

      expect(c.rate_limit(tenant_id)).to have_attributes(day_remaining: 500, day_source: :configured)
    end

    # #remaining is the optional half of the limiter contract; a limiter
    # written against 0.2.0 only has #acquire and must still work.
    it "tolerates a limiter that predates #remaining" do
      c = client(throttle: Object.new.tap { |o| def o.acquire(_key) = nil })

      expect(c.rate_limit(tenant_id).configured).to be_nil
    end

    it "requires a tenant id" do
      expect { client.rate_limit("") }.to raise_error(ArgumentError, /tenant_id is required/)
    end
  end

  describe "tracking categories" do
    let(:endpoint) { "https://api.xero.com/api.xro/2.0/TrackingCategories" }
    let(:payload) do
      {
        "TrackingCategories" => [
          {
            "TrackingCategoryID" => "tc1",
            "Name"               => "Region",
            "Status"             => "ACTIVE",
            "Options"            => [{ "TrackingOptionID" => "to1", "Name" => "Eastside", "Status" => "ACTIVE" }]
          }
        ]
      }
    end

    it "lists them for a tenant" do
      stub_request(:get, endpoint)
        .with(headers: { "Xero-Tenant-Id" => tenant_id })
        .to_return(status: 200, body: JSON.dump(payload), headers: json_headers)

      expect(client.tracking_categories(tenant_id).first).to be_a(XeroKiwi::Accounting::TrackingCategory)
    end

    it "hydrates the nested options" do
      stub_request(:get, endpoint).to_return(status: 200, body: JSON.dump(payload), headers: json_headers)

      expect(client.tracking_categories(tenant_id).first.options.first.name).to eq("Eastside")
    end

    it "fetches a single category by id" do
      stub_request(:get, "#{endpoint}/tc1")
        .to_return(status: 200, body: JSON.dump(payload), headers: json_headers)

      expect(client.tracking_category(tenant_id, "tc1").name).to eq("Region")
    end

    it "requires a category id" do
      expect { client.tracking_category(tenant_id, "") }
        .to raise_error(ArgumentError, /tracking_category_id is required/)
    end
  end
end
