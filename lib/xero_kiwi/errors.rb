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

  class RateLimitError < APIError
    attr_reader :retry_after, :problem

    def initialize(status, body, retry_after: nil, problem: nil)
      @retry_after = retry_after
      @problem     = problem
      super(status, body, "Xero rate limit hit (#{problem || "unknown"}); retry after #{retry_after}s")
    end
  end
end
