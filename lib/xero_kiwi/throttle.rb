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

    # Raised immediately (no sleep) when the per-day bucket is exhausted.
    #
    # `retry_after` is the wait for ONE token, and it is seconds, not hours —
    # the day bucket trickles like the minute bucket rather than resetting on
    # a boundary. At `per_day: 4_900` a token accrues every 17.6s
    # (86_400_000ms / 4_900). There is no reset in the arithmetic.
    #
    # Re-enqueueing rather than blocking is still the right move, but for a
    # different reason than the wait length: a sync needing several hundred
    # more calls would sleep 17.6s for each of them, which is hours in
    # aggregate even though each individual wait is short.
    #
    # Do not conflate this with Xero's own `Retry-After` on a daily 429,
    # which reflects Xero's limit rather than your configured one and can be
    # genuinely long. Anything recording a durable back-off should keep the
    # two distinguishable — see docs/retries-and-rate-limits.md.
    #
    # Shape mirrors RateLimitError so existing Xero rate-limit handling
    # applies.
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
