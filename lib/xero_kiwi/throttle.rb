# frozen_string_literal: true

module XeroKiwi
  # Proactive rate-limit coordination for multi-process callers hitting the
  # same Xero tenant. The retry middleware in Client handles reactive 429s;
  # this module blocks *before* a request goes out so 429s become rare.
  #
  # See docs/throttling.md for the full story.
  module Throttle
    class Error < XeroKiwi::Error; end

    # Raised when the per-minute bucket is empty and the caller has already
    # waited longer than the limiter's configured max_wait. The right fix is
    # usually to slow the caller down or raise headroom; swallowing this
    # quietly tends to hide the problem.
    #
    # Carries `tenant_id` and `retry_after` so a caller recording a durable
    # back-off signal has both facts without inferring either from context.
    class Timeout < Error
      attr_reader :tenant_id, :retry_after

      # `message` stays positional and first so `raise Throttle::Timeout, "…"`
      # keeps working for anyone who was doing that.
      def initialize(message = nil, tenant_id: nil, retry_after: nil)
        @tenant_id   = tenant_id
        @retry_after = retry_after
        super(message || "timed out waiting for a rate-limit token")
      end
    end

    # Raised immediately (no sleep) when the per-day bucket is exhausted. The
    # wait until reset is typically measured in hours, so blocking the caller
    # is the wrong move — re-enqueue the job at `retry_after` instead. Shape
    # mirrors RateLimitError so existing Xero rate-limit handling applies.
    class DailyLimitExhausted < Error
      attr_reader :retry_after, :tenant_id

      def initialize(retry_after:, tenant_id: nil)
        @retry_after = retry_after
        @tenant_id   = tenant_id
        super("Xero daily rate limit exhausted; retry in #{retry_after.round}s")
      end
    end
  end
end

require_relative "throttle/null_limiter"
require_relative "throttle/redis_token_bucket"
require_relative "throttle/middleware"
