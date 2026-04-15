# frozen_string_literal: true

require "faraday"
require "faraday/retry"

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
      throttle: nil
    )
      @token            = Token.new(
        access_token:  access_token,
        refresh_token: refresh_token,
        expires_at:    expires_at
      )
      @client_id        = client_id
      @client_secret    = client_secret
      @on_token_refresh = on_token_refresh
      @adapter          = adapter
      @user_agent       = user_agent
      @retry_options    = DEFAULT_RETRY_OPTIONS.merge(retry_options)
      @throttle         = throttle || Throttle::NullLimiter.new
      @refresh_mutex    = Mutex.new
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
        Accounting::Organisation.from_response(response.body)
      end
    end

    # Fetches the Users for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/users
    def users(tenant_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/Users") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::User.from_response(response.body)
      end
    end

    # Fetches a single User by ID for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/users
    def user(tenant_id, user_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?
      raise ArgumentError, "user_id is required" if user_id.nil? || user_id.to_s.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/Users/#{user_id}") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::User.from_response(response.body).first
      end
    end

    # Fetches the Contacts for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/contacts
    def contacts(tenant_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/Contacts") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::Contact.from_response(response.body)
      end
    end

    # Fetches a single Contact by ID for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/contacts
    def contact(tenant_id, contact_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?
      raise ArgumentError, "contact_id is required" if contact_id.nil? || contact_id.to_s.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/Contacts/#{contact_id}") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::Contact.from_response(response.body).first
      end
    end

    # Fetches the Contact Groups for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/contactgroups
    def contact_groups(tenant_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/ContactGroups") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::ContactGroup.from_response(response.body)
      end
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
        Accounting::ContactGroup.from_response(response.body).first
      end
    end

    # Fetches the Prepayments for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/prepayments
    def prepayments(tenant_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/Prepayments") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::Prepayment.from_response(response.body)
      end
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
        Accounting::Prepayment.from_response(response.body).first
      end
    end

    # Fetches the Credit Notes for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/creditnotes
    def credit_notes(tenant_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/CreditNotes") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::CreditNote.from_response(response.body)
      end
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
        Accounting::CreditNote.from_response(response.body).first
      end
    end

    # Fetches the Overpayments for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/overpayments
    def overpayments(tenant_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/Overpayments") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::Overpayment.from_response(response.body)
      end
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
        Accounting::Overpayment.from_response(response.body).first
      end
    end

    # Fetches the Payments for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/payments
    def payments(tenant_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/Payments") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::Payment.from_response(response.body)
      end
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
        Accounting::Payment.from_response(response.body).first
      end
    end

    # Fetches the Invoices for the given tenant. Accepts a tenant-id
    # string or a XeroKiwi::Connection (we use its tenant_id).
    # See: https://developer.xero.com/documentation/api/accounting/invoices
    def invoices(tenant_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/Invoices") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::Invoice.from_response(response.body)
      end
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
        Accounting::Invoice.from_response(response.body).first
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
    def branding_themes(tenant_id)
      tid = extract_tenant_id(tenant_id)
      raise ArgumentError, "tenant_id is required" if tid.nil? || tid.empty?

      with_authenticated_request do
        response = http.get("/api.xro/2.0/BrandingThemes") do |req|
          req.headers["Xero-Tenant-Id"] = tid
        end
        Accounting::BrandingTheme.from_response(response.body)
      end
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
        Accounting::BrandingTheme.from_response(response.body).first
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
    #   3. Throttle — blocks before each attempt until a per-tenant token is
    #      available. Below Retry so every retry also consumes a token.
    #   4. JSON — parses the response body so handlers downstream get a Hash.
    #   5. Adapter — actually makes the HTTP call.
    #
    # Putting ResponseHandler outside Retry is the key trick: it means a 429
    # gets retried by Faraday before we ever raise RateLimitError, and the
    # exception only fires once we've truly given up.
    def build_http
      Faraday.new(url: BASE_URL) do |f|
        f.use ResponseHandler
        f.request :retry, @retry_options
        f.use Throttle::Middleware, @throttle
        f.response :json, content_type: /\bjson/
        f.adapter(@adapter || Faraday.default_adapter)

        f.headers["Authorization"] = "Bearer #{@token.access_token}"
        f.headers["Accept"]        = "application/json"
        f.headers["User-Agent"]    = @user_agent
      end
    end

    # Faraday middleware that maps non-2xx responses onto our exception
    # hierarchy. Lives outside the retry middleware so it only fires on the
    # final response.
    class ResponseHandler < Faraday::Middleware
      def on_complete(env)
        return if (200..299).cover?(env.status)

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
          problem:     env.response_headers["x-rate-limit-problem"]
        )
      end
    end
  end
end
