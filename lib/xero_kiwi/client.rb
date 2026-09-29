# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require "time"

module XeroKiwi
  # Entry point for talking to Xero. Holds the OAuth2 token state, knows how
  # to refresh it (when given client credentials), and exposes resource
  # methods that auto-refresh before each request.
  #
  #   # Simple — access token only, no refresh capability.
  #   client = XeroKiwi::Client.new(access_token: "ya29...")
  #
  #   # Full — refresh-capable, with persistence callback.
  #   client = XeroKiwi::Client.new(
  #     access_token:     creds.access_token,
  #     refresh_token:    creds.refresh_token,
  #     expires_at:       creds.expires_at,
  #     client_id:        ENV["XERO_CLIENT_ID"],
  #     client_secret:    ENV["XERO_CLIENT_SECRET"],
  #     on_token_refresh: ->(token) { creds.update!(token.to_h) }
  #   )
  #
  #   client.token             # => XeroKiwi::Token
  #   client.token.expired?    # => false
  #   client.refresh_token!    # manual force refresh
  #   client.connections       # auto-refreshes if expiring; reactive on 401
  class Client
    BASE_URL           = "https://api.xero.com"
    DEFAULT_USER_AGENT = "XeroKiwi/#{XeroKiwi::VERSION} (+https://github.com/douglasgreyling/xero-kiwi)".freeze

    # HTTP statuses we treat as transient. faraday-retry honours Retry-After
    # automatically when the status is in this list.
    RETRY_STATUSES = [429, 502, 503, 504].freeze

    DEFAULT_RETRY_OPTIONS = {
      max:                 4,
      interval:            0.5,
      interval_randomness: 0.5,
      backoff_factor:      2,
      retry_statuses:      RETRY_STATUSES,
      methods:             %i[get head options put delete post],
      # Faraday::RetriableResponse is the *internal* signal faraday-retry uses
      # to flag a status-code retry. It MUST be in this list, or the middleware
      # can't catch its own retry signal and 429s/503s never get retried.
      exceptions:          [
        Faraday::ConnectionFailed,
        Faraday::TimeoutError,
        Faraday::RetriableResponse,
        Errno::ETIMEDOUT
      ]
    }.freeze

    attr_reader :token

    def initialize(
      access_token:,
      refresh_token: nil,
      expires_at: nil,
      client_id: nil,
      client_secret: nil,
      on_token_refresh: nil,
      adapter: nil,
      user_agent: DEFAULT_USER_AGENT,
      retry_options: {},
      throttle: nil,
      page_size: nil,
      retain_raw: false
    )
      @token            = Token.new(access_token: access_token, refresh_token: refresh_token, expires_at: expires_at)
      @client_id        = client_id
      @client_secret    = client_secret
      @on_token_refresh = on_token_refresh
      @adapter          = adapter
      @user_agent       = user_agent
      @retry_options    = DEFAULT_RETRY_OPTIONS.merge(retry_options)
      @throttle         = throttle || XeroKiwi.default_throttle || Throttle::NullLimiter.new
      @page_size        = page_size
      @retain_raw       = retain_raw
      @rate_limits      = RateLimitStore.new
      @refresh_mutex    = Mutex.new
    end

    # Quota remaining for a tenant, blended from Xero's last reported headers
    # and the configured throttle bucket — whichever is stricter. See
    # XeroKiwi::RateLimit.
    #
    #   break if client.rate_limit(tid).day_below?(1_000)
    def rate_limit(tenant_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?

      RateLimit.new(reported: @rate_limits.fetch(tid), configured: configured_rate_limit(tid))
    end

    # Fetches the list of tenants the current access token has access to.
    # See: https://developer.xero.com/documentation/best-practices/managing-connections/connections
    def connections
      with_authenticated_request do
        response = http.get("/connections")
        Connection.from_response(response.body)
      end
    end

    # Fetches the Organisation for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/organisation
    def organisation(tenant_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/Organisation") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::Organisation.from_response(response.body, retain_raw: @retain_raw)
      end
    end

    # Fetches the Users for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/users
    def users(tenant_id, where: nil, order: nil, page_size: nil, page: nil, modified_since: nil)
      list_request(
        path:           "/api.xro/2.0/Users",
        tenant_id:      tenant_id,
        resource_class: Accounting::User,
        where:          where,
        order:          order,
        page:           page,
        page_size:      page_size,
        modified_since: modified_since
      )
    end

    # Yields every User across all pages, driving `#users` with
    # `page:` until an empty or short page signals the end. Returns an
    # Enumerator when no block is given.
    def each_user(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_user, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      each_user_page(tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) { |pg| pg.each(&block) }
    end

    # Same walk as `#each_user`, but yields each XeroKiwi::Page rather
    # than its items. Pair `page.page` with `start_page:` to make a sync
    # resumable: record the page number in the same transaction that stores
    # the rows, and a crash can't leave a marker ahead of the data.
    def each_user_page(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_user_page, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      walk_pages(:users, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since, &block)
    end

    # Fetches a single User by ID for the given tenant. Accepts a
    # tenant-id string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/users
    def user(tenant_id, user_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?
      raise ArgumentError, "user_id is required" if user_id.nil? || user_id.to_s.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/Users/#{user_id}") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::User.from_response(response.body, retain_raw: @retain_raw).first
      end
    end

    # Fetches the Contacts for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/contacts
    def contacts(tenant_id, where: nil, order: nil, page_size: nil, include_archived: nil, page: nil, modified_since: nil)
      extra_params = {}

      extra_params["includeArchived"] = include_archived unless include_archived.nil?

      list_request(
        path:           "/api.xro/2.0/Contacts",
        tenant_id:      tenant_id,
        resource_class: Accounting::Contact,
        where:          where,
        order:          order,
        page:           page,
        page_size:      page_size,
        modified_since: modified_since,
        extra_params:   extra_params
      )
    end

    # Yields every Contact across all pages, driving `#contacts` with
    # `page:` until an empty or short page signals the end. Returns an
    # Enumerator when no block is given.
    def each_contact(tenant_id, where: nil, order: nil, page_size: nil, include_archived: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_contact, tenant_id, where: where, order: order, page_size: page_size, include_archived: include_archived, start_page: start_page, modified_since: modified_since) unless block

      each_contact_page(tenant_id, where: where, order: order, page_size: page_size, include_archived: include_archived, start_page: start_page, modified_since: modified_since) { |pg| pg.each(&block) }
    end

    # Same walk as `#each_contact`, but yields each XeroKiwi::Page rather
    # than its items. Pair `page.page` with `start_page:` to make a sync
    # resumable: record the page number in the same transaction that stores
    # the rows, and a crash can't leave a marker ahead of the data.
    def each_contact_page(tenant_id, where: nil, order: nil, page_size: nil, include_archived: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_contact_page, tenant_id, where: where, order: order, page_size: page_size, include_archived: include_archived, start_page: start_page, modified_since: modified_since) unless block

      walk_pages(:contacts, tenant_id, where: where, order: order, page_size: page_size, include_archived: include_archived, start_page: start_page, modified_since: modified_since, &block)
    end

    # Fetches a single Contact by ID for the given tenant. Accepts a
    # tenant-id string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/contacts
    def contact(tenant_id, contact_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?
      raise ArgumentError, "contact_id is required" if contact_id.nil? || contact_id.to_s.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/Contacts/#{contact_id}") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::Contact.from_response(response.body, retain_raw: @retain_raw).first
      end
    end

    # Fetches the Contact Groups for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/contactgroups
    def contact_groups(tenant_id, where: nil, order: nil, page_size: nil, page: nil, modified_since: nil)
      list_request(
        path:           "/api.xro/2.0/ContactGroups",
        tenant_id:      tenant_id,
        resource_class: Accounting::ContactGroup,
        where:          where,
        order:          order,
        page:           page,
        page_size:      page_size,
        modified_since: modified_since
      )
    end

    # Yields every Contact Group across all pages, driving `#contact_groups` with
    # `page:` until an empty or short page signals the end. Returns an
    # Enumerator when no block is given.
    def each_contact_group(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_contact_group, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      each_contact_group_page(tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) { |pg| pg.each(&block) }
    end

    # Same walk as `#each_contact_group`, but yields each XeroKiwi::Page rather
    # than its items. Pair `page.page` with `start_page:` to make a sync
    # resumable: record the page number in the same transaction that stores
    # the rows, and a crash can't leave a marker ahead of the data.
    def each_contact_group_page(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_contact_group_page, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      walk_pages(:contact_groups, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since, &block)
    end

    # Fetches a single Contact Group by ID for the given tenant. Accepts a
    # tenant-id string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/contactgroups
    def contact_group(tenant_id, contact_group_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?
      raise ArgumentError, "contact_group_id is required" if contact_group_id.nil? || contact_group_id.to_s.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/ContactGroups/#{contact_group_id}") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::ContactGroup.from_response(response.body, retain_raw: @retain_raw).first
      end
    end

    # Fetches the Prepayments for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/prepayments
    def prepayments(tenant_id, where: nil, order: nil, page_size: nil, page: nil, modified_since: nil)
      list_request(
        path:           "/api.xro/2.0/Prepayments",
        tenant_id:      tenant_id,
        resource_class: Accounting::Prepayment,
        where:          where,
        order:          order,
        page:           page,
        page_size:      page_size,
        modified_since: modified_since
      )
    end

    # Yields every Prepayment across all pages, driving `#prepayments` with
    # `page:` until an empty or short page signals the end. Returns an
    # Enumerator when no block is given.
    def each_prepayment(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_prepayment, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      each_prepayment_page(tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) { |pg| pg.each(&block) }
    end

    # Same walk as `#each_prepayment`, but yields each XeroKiwi::Page rather
    # than its items. Pair `page.page` with `start_page:` to make a sync
    # resumable: record the page number in the same transaction that stores
    # the rows, and a crash can't leave a marker ahead of the data.
    def each_prepayment_page(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_prepayment_page, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      walk_pages(:prepayments, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since, &block)
    end

    # Fetches a single Prepayment by ID for the given tenant. Accepts a
    # tenant-id string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/prepayments
    def prepayment(tenant_id, prepayment_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?
      raise ArgumentError, "prepayment_id is required" if prepayment_id.nil? || prepayment_id.to_s.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/Prepayments/#{prepayment_id}") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::Prepayment.from_response(response.body, retain_raw: @retain_raw).first
      end
    end

    # Fetches the Credit Notes for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/creditnotes
    def credit_notes(tenant_id, where: nil, order: nil, page_size: nil, page: nil, modified_since: nil)
      list_request(
        path:           "/api.xro/2.0/CreditNotes",
        tenant_id:      tenant_id,
        resource_class: Accounting::CreditNote,
        where:          where,
        order:          order,
        page:           page,
        page_size:      page_size,
        modified_since: modified_since
      )
    end

    # Yields every Credit Note across all pages, driving `#credit_notes` with
    # `page:` until an empty or short page signals the end. Returns an
    # Enumerator when no block is given.
    def each_credit_note(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_credit_note, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      each_credit_note_page(tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) { |pg| pg.each(&block) }
    end

    # Same walk as `#each_credit_note`, but yields each XeroKiwi::Page rather
    # than its items. Pair `page.page` with `start_page:` to make a sync
    # resumable: record the page number in the same transaction that stores
    # the rows, and a crash can't leave a marker ahead of the data.
    def each_credit_note_page(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_credit_note_page, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      walk_pages(:credit_notes, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since, &block)
    end

    # Fetches a single Credit Note by ID for the given tenant. Accepts a
    # tenant-id string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/creditnotes
    def credit_note(tenant_id, credit_note_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?
      raise ArgumentError, "credit_note_id is required" if credit_note_id.nil? || credit_note_id.to_s.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/CreditNotes/#{credit_note_id}") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::CreditNote.from_response(response.body, retain_raw: @retain_raw).first
      end
    end

    # Fetches the Overpayments for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/overpayments
    def overpayments(tenant_id, where: nil, order: nil, page_size: nil, page: nil, modified_since: nil)
      list_request(
        path:           "/api.xro/2.0/Overpayments",
        tenant_id:      tenant_id,
        resource_class: Accounting::Overpayment,
        where:          where,
        order:          order,
        page:           page,
        page_size:      page_size,
        modified_since: modified_since
      )
    end

    # Yields every Overpayment across all pages, driving `#overpayments` with
    # `page:` until an empty or short page signals the end. Returns an
    # Enumerator when no block is given.
    def each_overpayment(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_overpayment, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      each_overpayment_page(tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) { |pg| pg.each(&block) }
    end

    # Same walk as `#each_overpayment`, but yields each XeroKiwi::Page rather
    # than its items. Pair `page.page` with `start_page:` to make a sync
    # resumable: record the page number in the same transaction that stores
    # the rows, and a crash can't leave a marker ahead of the data.
    def each_overpayment_page(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_overpayment_page, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      walk_pages(:overpayments, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since, &block)
    end

    # Fetches a single Overpayment by ID for the given tenant. Accepts a
    # tenant-id string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/overpayments
    def overpayment(tenant_id, overpayment_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?
      raise ArgumentError, "overpayment_id is required" if overpayment_id.nil? || overpayment_id.to_s.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/Overpayments/#{overpayment_id}") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::Overpayment.from_response(response.body, retain_raw: @retain_raw).first
      end
    end

    # Fetches the Payments for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/payments
    def payments(tenant_id, where: nil, order: nil, page_size: nil, page: nil, modified_since: nil)
      list_request(
        path:           "/api.xro/2.0/Payments",
        tenant_id:      tenant_id,
        resource_class: Accounting::Payment,
        where:          where,
        order:          order,
        page:           page,
        page_size:      page_size,
        modified_since: modified_since
      )
    end

    # Yields every Payment across all pages, driving `#payments` with
    # `page:` until an empty or short page signals the end. Returns an
    # Enumerator when no block is given.
    def each_payment(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_payment, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      each_payment_page(tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) { |pg| pg.each(&block) }
    end

    # Same walk as `#each_payment`, but yields each XeroKiwi::Page rather
    # than its items. Pair `page.page` with `start_page:` to make a sync
    # resumable: record the page number in the same transaction that stores
    # the rows, and a crash can't leave a marker ahead of the data.
    def each_payment_page(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_payment_page, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      walk_pages(:payments, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since, &block)
    end

    # Fetches a single Payment by ID for the given tenant. Accepts a
    # tenant-id string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/payments
    def payment(tenant_id, payment_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?
      raise ArgumentError, "payment_id is required" if payment_id.nil? || payment_id.to_s.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/Payments/#{payment_id}") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::Payment.from_response(response.body, retain_raw: @retain_raw).first
      end
    end

    # Fetches the Invoices for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/invoices
    def invoices(tenant_id, where: nil, order: nil, page_size: nil, page: nil, modified_since: nil)
      list_request(
        path:           "/api.xro/2.0/Invoices",
        tenant_id:      tenant_id,
        resource_class: Accounting::Invoice,
        where:          where,
        order:          order,
        page:           page,
        page_size:      page_size,
        modified_since: modified_since
      )
    end

    # Yields every Invoice across all pages, driving `#invoices` with
    # `page:` until an empty or short page signals the end. Returns an
    # Enumerator when no block is given.
    def each_invoice(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_invoice, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      each_invoice_page(tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) { |pg| pg.each(&block) }
    end

    # Same walk as `#each_invoice`, but yields each XeroKiwi::Page rather
    # than its items. Pair `page.page` with `start_page:` to make a sync
    # resumable: record the page number in the same transaction that stores
    # the rows, and a crash can't leave a marker ahead of the data.
    def each_invoice_page(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_invoice_page, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      walk_pages(:invoices, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since, &block)
    end

    # Fetches a single Invoice by ID for the given tenant. Accepts a
    # tenant-id string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/invoices
    def invoice(tenant_id, invoice_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?
      raise ArgumentError, "invoice_id is required" if invoice_id.nil? || invoice_id.to_s.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/Invoices/#{invoice_id}") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::Invoice.from_response(response.body, retain_raw: @retain_raw).first
      end
    end

    # Fetches the online invoice URL for a sales (ACCREC) invoice. Returns
    # the URL string, or nil if not available. Cannot be used on DRAFT invoices.
    # See: https://developer.xero.com/documentation/api/accounting/invoices
    def online_invoice_url(tenant_id, invoice_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?
      raise ArgumentError, "invoice_id is required" if invoice_id.nil? || invoice_id.to_s.empty?

      data = with_authenticated_request do
        http.get("/api.xro/2.0/Invoices/#{invoice_id}/OnlineInvoice") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
      end
      data.body.dig("OnlineInvoices", 0, "OnlineInvoiceUrl")
    end

    # Fetches the Branding Themes for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/brandingthemes
    def branding_themes(tenant_id, where: nil, order: nil, page_size: nil, page: nil, modified_since: nil)
      list_request(
        path:           "/api.xro/2.0/BrandingThemes",
        tenant_id:      tenant_id,
        resource_class: Accounting::BrandingTheme,
        where:          where,
        order:          order,
        page:           page,
        page_size:      page_size,
        modified_since: modified_since
      )
    end

    # Yields every Branding Theme across all pages, driving `#branding_themes` with
    # `page:` until an empty or short page signals the end. Returns an
    # Enumerator when no block is given.
    def each_branding_theme(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_branding_theme, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      each_branding_theme_page(tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) { |pg| pg.each(&block) }
    end

    # Same walk as `#each_branding_theme`, but yields each XeroKiwi::Page rather
    # than its items. Pair `page.page` with `start_page:` to make a sync
    # resumable: record the page number in the same transaction that stores
    # the rows, and a crash can't leave a marker ahead of the data.
    def each_branding_theme_page(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_branding_theme_page, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      walk_pages(:branding_themes, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since, &block)
    end

    # Fetches a single Branding Theme by ID for the given tenant. Accepts a
    # tenant-id string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/brandingthemes
    def branding_theme(tenant_id, branding_theme_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?
      raise ArgumentError, "branding_theme_id is required" if branding_theme_id.nil? || branding_theme_id.to_s.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/BrandingThemes/#{branding_theme_id}") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::BrandingTheme.from_response(response.body, retain_raw: @retain_raw).first
      end
    end

    # Fetches the Tracking Categories for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/trackingcategories
    def tracking_categories(tenant_id, where: nil, order: nil, page_size: nil, page: nil, modified_since: nil)
      list_request(
        path:           "/api.xro/2.0/TrackingCategories",
        tenant_id:      tenant_id,
        resource_class: Accounting::TrackingCategory,
        where:          where,
        order:          order,
        page:           page,
        page_size:      page_size,
        modified_since: modified_since
      )
    end

    # Yields every Tracking Category across all pages, driving `#tracking_categories` with
    # `page:` until an empty or short page signals the end. Returns an
    # Enumerator when no block is given.
    def each_tracking_category(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_tracking_category, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      each_tracking_category_page(tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) { |pg| pg.each(&block) }
    end

    # Same walk as `#each_tracking_category`, but yields each XeroKiwi::Page rather
    # than its items. Pair `page.page` with `start_page:` to make a sync
    # resumable: record the page number in the same transaction that stores
    # the rows, and a crash can't leave a marker ahead of the data.
    def each_tracking_category_page(tenant_id, where: nil, order: nil, page_size: nil, start_page: 1, modified_since: nil, &block)
      return to_enum(:each_tracking_category_page, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since) unless block

      walk_pages(:tracking_categories, tenant_id, where: where, order: order, page_size: page_size, start_page: start_page, modified_since: modified_since, &block)
    end

    # Fetches a single Tracking Category by ID for the given tenant. Accepts a
    # tenant-id string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/trackingcategories
    def tracking_category(tenant_id, tracking_category_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?
      raise ArgumentError, "tracking_category_id is required" if tracking_category_id.nil? || tracking_category_id.to_s.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/TrackingCategories/#{tracking_category_id}") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::TrackingCategory.from_response(response.body, retain_raw: @retain_raw).first
      end
    end

    # Disconnects a tenant. Accepts either a XeroKiwi::Connection (we use its
    # `id`) or a raw connection-id string. Returns true on the 204. The
    # access token may still be valid for *other* connections after this —
    # only the named tenant is detached.
    def delete_connection(connection_or_id)
      id = extract_connection_id(connection_or_id)
      raise ArgumentError, "connection id is required" if id.nil? || id.empty?

      with_authenticated_request do
        http.delete("/connections/#{id}")
        true
      end
    end

    # Revokes the current refresh token at Xero, invalidating it and every
    # access token issued from it. Use this for "disconnect Xero" / logout
    # flows. After this call, treat the client as dead — subsequent API
    # calls will 401. The caller is responsible for cleaning up any
    # persisted credential record.
    def revoke_token!
      raise TokenRefreshError.new(nil, nil, "client has no refresh capability") unless can_refresh?

      revoker.revoke_token(refresh_token: @token.refresh_token)
      true
    end

    # Forces a refresh regardless of expiry. Returns the new Token. Raises
    # TokenRefreshError if refresh credentials are missing or if Xero rejects
    # the refresh.
    def refresh_token!
      raise TokenRefreshError.new(nil, nil, "client has no refresh capability") unless can_refresh?

      @refresh_mutex.synchronize { perform_refresh }
    end

    # True if this client was constructed with refresh credentials AND the
    # current token still carries a refresh_token to use.
    def can_refresh?
      !@client_id.nil? && !@client_secret.nil? && @token.refreshable?
    end

    private

    # Canonical list request. Compiles `where` / `order` from the resource's
    # query_fields, sends `page` straight through, and translates
    # `modified_since` to the `If-Modified-Since` header. Wraps the response
    # in a XeroKiwi::Page.
    def list_request(path:, tenant_id:, resource_class:, # rubocop:disable Metrics/AbcSize
                     where:, order:, page:, page_size:, modified_since:, extra_params: {})
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?

      params = list_params(resource_class, where: where, order: order, page: page, page_size: page_size)
      params = params.merge(extra_params)

      with_authenticated_request do
        response = http.get(path, params) do |req|
          req.headers["Xero-Tenant-Id"]    = tid
          req.headers["If-Modified-Since"] = modified_since.utc.httpdate if modified_since
        end
        build_page(response, resource_class)
      end
    end

    def list_params(resource_class, where:, order:, page:, page_size:)
      size   = page_size || @page_size
      fields = resource_class.query_fields
      params = {}

      params["where"]    = Query::Filter.compile(where, fields: fields) if where
      params["order"]    = Query::Order.compile(order, fields: fields) if order
      params["page"]     = page if page
      params["pageSize"] = size if size
      params
    end

    def build_page(response, resource_class)
      return Page.new(items: []) if response.status == 304

      items    = resource_class.from_response(response.body, retain_raw: @retain_raw)
      pag      = response.body.is_a?(Hash) ? response.body["pagination"] : nil
      reported = pag&.dig("pageSize")
      counted  = pag&.dig("itemCount")

      Page.new(
        items:              items,
        page:               pag&.dig("page") || 1,
        page_size:          reported || items.size,
        item_count:         counted  || items.size,
        total_count:        counted,
        reported_page_size: reported
      )
    end

    # Shared lazy page-walker powering every `each_*` and `each_*_page`
    # helper. Calls the given list method repeatedly from `start_page`,
    # yielding whole Pages, until a page comes back empty or short.
    #
    # "Short" is measured against Xero's own stated page size when the
    # response carried a pagination envelope, and otherwise against the
    # largest page seen so far in this walk. Deliberately NOT against the
    # requested page size: Xero clamps a request above an endpoint's maximum,
    # so asking for 2000 where the cap is 1000 would make the very first page
    # look short and end the walk after one page — silently truncating the
    # sync. A measured yardstick can't do that. The cost is one extra request
    # when the whole result fits in a single page and no envelope came back,
    # since there's then nothing to compare against.
    def walk_pages(list_method, tenant_id, start_page:, **)
      largest_seen = nil

      (start_page..Float::INFINITY).lazy.each do |p|
        pg = send(list_method, tenant_id, page: p, **)
        break if pg.empty?

        yield pg

        largest_seen = pg.size if largest_seen.nil? || pg.size > largest_seen
        yardstick    = pg.reported_page_size || largest_seen
        break if pg.size < yardstick
      end
    end

    # Wraps each API call with proactive + reactive token refresh:
    #
    # - Proactive: if the current token is expiring within the default window,
    #   refresh BEFORE the request fires. This covers the common case.
    # - Reactive: if the request still 401s (e.g. our clock drifted, or Xero
    #   revoked the token early), refresh and retry exactly once. The `retried`
    #   flag prevents an infinite loop.
    def with_authenticated_request
      ensure_fresh_token!
      retried = false
      begin
        yield
      rescue AuthenticationError
        raise if retried || !can_refresh?

        retried = true
        refresh_token!
        retry
      end
    end

    # Auto-refresh path. Cheap to call before every request: only takes the
    # mutex if the token is actually expiring, then double-checks inside the
    # mutex to dedupe concurrent refreshes from different threads.
    def ensure_fresh_token!
      return unless can_refresh?
      return unless @token.expiring_soon?

      @refresh_mutex.synchronize do
        perform_refresh if @token.expiring_soon?
      end
    end

    # The actual refresh round-trip. Always called inside @refresh_mutex by
    # the two callers above. Mutating @token and the Faraday Authorization
    # header is the only place we touch shared state.
    def perform_refresh
      new_token = refresher.refresh(refresh_token: @token.refresh_token)
      @token    = new_token
      @_http&.headers&.[]=("Authorization", "Bearer #{new_token.access_token}")
      @on_token_refresh&.call(new_token)
      new_token
    end

    def refresher
      @_refresher ||= TokenRefresher.new(
        client_id:     @client_id,
        client_secret: @client_secret,
        adapter:       @adapter
      )
    end

    # Lightweight OAuth instance used solely for token revocation. We don't
    # need a redirect_uri for /connect/revocation, so this is constructed
    # without one. Built lazily so a Client that never revokes pays nothing.
    def revoker
      @_revoker ||= OAuth.new(
        client_id:     @client_id,
        client_secret: @client_secret,
        adapter:       @adapter
      )
    end

    # Nil unless the limiter implements the optional `#remaining` part of the
    # contract, and nil again if it couldn't answer (e.g. Redis is down and
    # the bucket failed open).
    def configured_rate_limit(tid)
      return nil unless @throttle.respond_to?(:remaining)

      counts = @throttle.remaining(tid)
      return nil if counts.nil?

      RateLimit::Configured.new(day: counts[:day], minute: counts[:minute])
    end

    def extract_connection_id(value)
      value.is_a?(Connection) ? value.id : value
    end

    def extract_tenant_id(value)
      value.is_a?(Connection) ? value.tenant_id : value
    end

    def http
      @_http ||= build_http
    end

    # Middleware order matters. Outbound runs top-to-bottom; inbound runs in
    # reverse. We want:
    #
    #   1. ResponseHandler (outermost) — converts the FINAL response status into
    #      a XeroKiwi exception, *after* retries have been exhausted.
    #   2. Retry — retries on 429/503 (respecting Retry-After) and on transport
    #      exceptions.
    #   3. RateLimitCapture — records Xero's quota headers. Below Retry so
    #      every attempt refreshes them, and below ResponseHandler so an error
    #      response is read before it's turned into an exception — a 429 is
    #      exactly when those headers matter most.
    #   4. Throttle — blocks before each attempt until a per-tenant token is
    #      available. Below Retry so every retry also consumes a token.
    #   5. JSON — parses the response body so handlers downstream get a Hash.
    #   6. Adapter — actually makes the HTTP call.
    #
    # Putting ResponseHandler outside Retry is the key trick: it means a 429
    # gets retried by Faraday before we ever raise RateLimitError, and the
    # exception only fires once we've truly given up.
    def build_http
      Faraday.new(url: BASE_URL) do |f|
        f.use ResponseHandler
        f.request :retry, @retry_options
        f.use RateLimitCapture, @rate_limits
        f.use Throttle::Middleware, @throttle
        f.response :json, content_type: /\bjson/
        f.adapter(@adapter || Faraday.default_adapter)

        f.headers["Authorization"] = "Bearer #{@token.access_token}"
        f.headers["Accept"]        = "application/json"
        f.headers["User-Agent"]    = @user_agent
      end
    end

    # Per-tenant store of the rate-limit figures Xero last reported. Written
    # from the Faraday middleware (any thread running a request) and read by
    # Client#rate_limit, so every access takes the mutex.
    class RateLimitStore
      def initialize
        @mutex     = Mutex.new
        @by_tenant = {}
      end

      def record(tenant_id, day:, minute:, app_minute:)
        return if day.nil? && minute.nil?

        reported                                   = RateLimit::Reported.new(day: day, minute: minute, app_minute: app_minute)
        @mutex.synchronize { @by_tenant[tenant_id] = reported }
      end

      def fetch(tenant_id)
        @mutex.synchronize { @by_tenant[tenant_id] }
      end
    end

    # Faraday middleware that records Xero's rate-limit headers per tenant.
    # Untenanted calls (/connections, OAuth) have no bucket to attribute the
    # figures to and are skipped.
    #
    # See: https://developer.xero.com/documentation/guides/oauth2/limits
    class RateLimitCapture < Faraday::Middleware
      TENANT_HEADER = "Xero-Tenant-Id"

      def initialize(app, store)
        super(app)
        @store = store
      end

      def on_complete(env)
        tenant_id = env.request_headers[TENANT_HEADER]
        return if tenant_id.nil? || tenant_id.empty?

        headers = env.response_headers
        return if headers.nil?

        @store.record(
          tenant_id,
          day:        header_int(headers, "X-DayLimit-Remaining"),
          minute:     header_int(headers, "X-MinLimit-Remaining"),
          app_minute: header_int(headers, "X-AppMinLimit-Remaining")
        )
      end

      private

      # Faraday's own header container is case-insensitive, so a direct
      # lookup is right in production. It is not right everywhere: a plain
      # Hash is case-sensitive, and Xero's headers come back cased
      # differently depending on who recorded them — a VCR cassette holds
      # `X-Daylimit-Remaining`, not `X-DayLimit-Remaining`. Missing them
      # would record nothing, and `day_below?` answers false when nothing is
      # known, so the failure is a quota check that silently measures
      # nothing. Scan on miss rather than rely on the container's manners.
      def header_int(headers, name)
        value = headers[name]
        value = scan_for(headers, name) if value.nil?

        value.nil? || value.to_s.empty? ? nil : value.to_i
      end

      def scan_for(headers, name)
        key = headers.keys.find { |candidate| candidate.to_s.casecmp?(name) }
        key && headers[key]
      end
    end

    # Faraday middleware that maps non-2xx responses onto our exception
    # hierarchy. Lives outside the retry middleware so it only fires on the
    # final response.
    class ResponseHandler < Faraday::Middleware
      def on_complete(env)
        # 304 Not Modified is a valid response to a conditional GET
        # (If-Modified-Since). Let it through so the list helper can
        # return an empty Page.
        return if (200..299).cover?(env.status) || env.status == 304

        raise error_for(env)
      end

      private

      def error_for(env)
        case env.status
        when 401      then AuthenticationError.new(env.status, env.body)
        when 429      then rate_limit_error(env)
        when 400..499 then ClientError.new(env.status, env.body)
        when 500..599 then ServerError.new(env.status, env.body)
        else APIError.new(env.status, env.body)
        end
      end

      def rate_limit_error(env)
        RateLimitError.new(
          env.status,
          env.body,
          retry_after: env.response_headers["retry-after"]&.to_f,
          problem:     env.response_headers["x-rate-limit-problem"],
          tenant_id:   env.request_headers[Throttle::Middleware::TENANT_HEADER]
        )
      end
    end
  end
end
