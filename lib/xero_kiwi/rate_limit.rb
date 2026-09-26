# frozen_string_literal: true

module XeroKiwi
  # How much Xero quota is left for a tenant, blended from the two sources
  # that know anything about it:
  #
  #   reported   - what Xero's rate-limit response headers said on the last
  #                call to this tenant. Reflects *every* consumer of that
  #                tenant's quota, including other applications. Nil until a
  #                request has actually been made.
  #   configured - what the throttle limiter has left in its own bucket.
  #                Reflects only calls made through this limiter, but it
  #                encodes the headroom you deliberately configured. Nil when
  #                throttling is off, or the limiter predates `#remaining`.
  #
  # Readings take **the stricter of the two**. A configured limit is a
  # ceiling we never exceed; a reported limit is reality we can't argue with.
  # If Xero reports 3,000 left but a bucket configured at 4,900/day holds 500
  # tokens, the answer is 500. If another app has burned the tenant's quota
  # so Xero reports 50 while our bucket still shows 2,000, the answer is 50.
  #
  #   rl = client.rate_limit(tenant_id)
  #   break if rl.day_below?(1_000)   # leave headroom for other processes
  class RateLimit
    Reported   = Struct.new(:day, :minute, :app_minute, keyword_init: true)
    Configured = Struct.new(:day, :minute, keyword_init: true)

    attr_reader :reported, :configured

    def initialize(reported: nil, configured: nil)
      @reported   = reported
      @configured = configured
    end

    def day_remaining
      strictest(reported&.day, configured&.day)
    end

    def minute_remaining
      strictest(reported&.minute, configured&.minute)
    end

    # False when nothing is known. Not knowing how much quota is left is not
    # a reason to halt a sync — and halting would break the common case,
    # where the first call is what populates `reported` in the first place.
    def day_below?(threshold)
      remaining = day_remaining
      !remaining.nil? && remaining < threshold
    end

    def minute_below?(threshold)
      remaining = minute_remaining
      !remaining.nil? && remaining < threshold
    end

    # Which source is currently the binding constraint, or nil when neither
    # has a reading. Useful for deciding whether a sync is being paced by
    # your own configuration or by Xero itself.
    def day_source
      binding_source(reported&.day, configured&.day)
    end

    def minute_source
      binding_source(reported&.minute, configured&.minute)
    end

    def known?
      !day_remaining.nil? || !minute_remaining.nil?
    end

    def inspect
      "#<#{self.class} day_remaining=#{day_remaining.inspect} (#{day_source.inspect}) " \
        "minute_remaining=#{minute_remaining.inspect} (#{minute_source.inspect})>"
    end

    private

    def strictest(*values)
      values.compact.min
    end

    def binding_source(reported_value, configured_value)
      return nil if reported_value.nil? && configured_value.nil?
      return :reported if configured_value.nil?
      return :configured if reported_value.nil?

      configured_value <= reported_value ? :configured : :reported
    end
  end
end
