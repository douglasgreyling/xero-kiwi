# frozen_string_literal: true

module XeroKiwi
  class Error < StandardError; end

  class APIError < Error
    attr_reader :status, :body

    def initialize(status, body, message = nil)
      @status = status
      @body   = body
      super(message || "Xero API responded with #{status}: #{body.inspect}")
    end
  end

  class AuthenticationError < APIError; end
  class ClientError < APIError; end
  class ServerError < APIError; end

  # Raised when refreshing the OAuth2 token fails — typically because the
  # refresh token has expired (60 days) or has already been rotated. Callers
  # should treat this as "the user must re-authorise" and surface accordingly.
  class TokenRefreshError < AuthenticationError; end

  # Raised when Xero returns 429 and the retry middleware has exhausted its
  # attempts. Carries everything needed to record a durable back-off signal —
  # which tenant, for how long, and which of Xero's three limits was hit —
  # without the caller inferring any of it from context. See
  # docs/retries-and-rate-limits.md for the persistence pattern.
  class RateLimitError < APIError
    attr_reader :retry_after, :problem, :tenant_id

    def initialize(status, body, retry_after: nil, problem: nil, tenant_id: nil)
      @retry_after = retry_after
      @problem     = problem
      @tenant_id   = tenant_id
      super(status, body, "Xero rate limit hit (#{problem || "unknown"}); retry after #{retry_after}s")
    end
  end
end
