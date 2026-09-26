# frozen_string_literal: true

require "digest"
require "redis"

module XeroKiwi
  module Throttle
    # Redis-backed token bucket, keyed per tenant. One Ruby instance is shared
    # across threads and (via Redis) across processes, so N Sidekiq workers
    # hitting the same Xero tenant cooperatively share a bucket.
    #
    # Two buckets per tenant — minute and (optionally) day — modelled as Redis
    # hashes with `tokens` and `last_refill_ms` fields. All bucket math runs
    # inside a Lua script so the read-modify-write is atomic server-side; doing
    # it in Ruby with separate GET/SET calls would race and leak tokens.
    #
    #   bucket = XeroKiwi::Throttle::RedisTokenBucket.new(
    #     redis:      Redis.new,
    #     per_minute: 55,        # Xero's default is 60; leave headroom.
    #     per_day:    4_900,     # optional. Xero's default is 5,000.
    #     max_wait:   30.0       # cap on how long acquire may block.
    #   )
    class RedisTokenBucket
      DEFAULT_NAMESPACE = "xero_kiwi:throttle"
      MINUTE_MS         = 60_000
      DAY_MS            = 86_400_000
      # Extra ms we sleep past a refill-time hint to avoid a busy loop.
      POLL_MS           = 1_000

      # Lua script. Input ARGV: now_ms, capacities... (minute, day?), window_ms... (minute, day?).
      # KEYS: bucket hash keys in the same order as capacities.
      #
      # Returns: { failed_bucket_index, wait_ms }
      #   {0, 0} = granted everywhere (decrements committed)
      #   {i, N} = bucket i (1-indexed) is empty; no decrements committed; wait N ms for it
      #
      # Granting is all-or-nothing across buckets: if any bucket is empty we
      # roll back, so a day-limit failure doesn't burn a minute token.
      LUA_SCRIPT = <<~LUA
        local now_ms = tonumber(ARGV[1])
        local n = #KEYS
        local new_tokens = {}

        for i = 1, n do
          local capacity  = tonumber(ARGV[1 + i])
          local window_ms = tonumber(ARGV[1 + n + i])
          local refill_per_ms = capacity / window_ms

          local data = redis.call("HMGET", KEYS[i], "tokens", "last_refill_ms")
          local tokens         = tonumber(data[1]) or capacity
          local last_refill_ms = tonumber(data[2]) or now_ms

          local elapsed = now_ms - last_refill_ms
          if elapsed < 0 then elapsed = 0 end
          tokens = math.min(capacity, tokens + elapsed * refill_per_ms)

          if tokens < 1 then
            local shortfall = 1 - tokens
            local wait_ms = math.ceil(shortfall / refill_per_ms)
            return { i, wait_ms }
          end

          new_tokens[i] = tokens - 1
        end

        for i = 1, n do
          local window_ms = tonumber(ARGV[1 + n + i])
          redis.call("HSET", KEYS[i], "tokens", new_tokens[i], "last_refill_ms", now_ms)
          redis.call("PEXPIRE", KEYS[i], window_ms * 2)
        end

        return { 0, 0 }
      LUA

      LUA_SHA = Digest::SHA1.hexdigest(LUA_SCRIPT)

      # Read-only sibling of LUA_SCRIPT: runs the same refill arithmetic but
      # commits nothing, so asking how much is left never costs a token.
      # Returns floored token counts in KEYS order (minute, day?).
      PEEK_SCRIPT = <<~LUA
        local now_ms = tonumber(ARGV[1])
        local n = #KEYS
        local out = {}

        for i = 1, n do
          local capacity  = tonumber(ARGV[1 + i])
          local window_ms = tonumber(ARGV[1 + n + i])
          local refill_per_ms = capacity / window_ms

          local data = redis.call("HMGET", KEYS[i], "tokens", "last_refill_ms")
          local tokens         = tonumber(data[1]) or capacity
          local last_refill_ms = tonumber(data[2]) or now_ms

          local elapsed = now_ms - last_refill_ms
          if elapsed < 0 then elapsed = 0 end
          tokens = math.min(capacity, tokens + elapsed * refill_per_ms)

          out[i] = math.floor(tokens)
        end

        return out
      LUA

      PEEK_SHA = Digest::SHA1.hexdigest(PEEK_SCRIPT)

      DEFAULT_CLOCK   = -> { (Process.clock_gettime(Process::CLOCK_REALTIME) * 1000).to_i }
      DEFAULT_SLEEPER = ->(seconds) { Kernel.sleep(seconds) }

      def initialize(redis:, per_minute:, per_day: nil, namespace: DEFAULT_NAMESPACE,
                     max_wait: 30.0, logger: nil, clock: DEFAULT_CLOCK, sleeper: DEFAULT_SLEEPER)
        raise ArgumentError, "per_minute must be > 0" unless per_minute.to_i.positive?
        raise ArgumentError, "per_day must be > 0 when given" if per_day && !per_day.to_i.positive?

        @redis      = redis
        @per_minute = per_minute.to_i
        @per_day    = per_day&.to_i
        @namespace  = namespace
        @max_wait   = max_wait.to_f
        @logger     = logger
        @clock      = clock
        @sleeper    = sleeper
      end

      # Blocks until a token is available in every configured bucket. Fails
      # open on Redis errors (logs and returns) so a dead Redis can't stop
      # the app — the reactive retry layer still catches any resulting 429s.
      def acquire(key)
        raise ArgumentError, "key is required" if key.nil? || key.to_s.empty?

        waited_ms = 0

        loop do
          failed, wait_ms = evaluate(key)
          return if failed.zero?

          waited_ms = handle_failure(failed, wait_ms, waited_ms)
        end
      rescue Redis::BaseError => e
        log_redis_failure(e)
        nil
      end

      # How many tokens each bucket currently holds, without spending one.
      # Returns `{ minute:, day: }` — `day` is nil when no per_day limit is
      # configured — or nil if Redis is unreachable, matching acquire's
      # fail-open behaviour.
      def remaining(key)
        raise ArgumentError, "key is required" if key.nil? || key.to_s.empty?

        keys, capacities, windows = bucket_args(key)
        minute, day               = run_script(PEEK_SCRIPT, PEEK_SHA, keys, [@clock.call, *capacities, *windows])

        { minute: minute, day: day }
      rescue Redis::BaseError => e
        log_redis_failure(e)
        nil
      end

      private

      def handle_failure(failed, wait_ms, waited_ms)
        case failed
        when 1 then wait_for_minute_bucket(wait_ms, waited_ms)
        when 2 then raise Throttle::DailyLimitExhausted.new(retry_after: wait_ms / 1000.0)
        end
      end

      def wait_for_minute_bucket(wait_ms, waited_ms)
        if (waited_ms + wait_ms) / 1000.0 > @max_wait
          raise Throttle::Timeout,
                "waited #{(waited_ms / 1000.0).round(2)}s for rate-limit token, exceeds max_wait=#{@max_wait}s"
        end

        @sleeper.call((wait_ms + POLL_MS) / 1000.0)
        waited_ms + wait_ms + POLL_MS
      end

      def evaluate(key)
        keys, capacities, windows = bucket_args(key)

        run_script(LUA_SCRIPT, LUA_SHA, keys, [@clock.call, *capacities, *windows])
      end

      # evalsha first so the script body isn't shipped on every call; fall
      # back to a full eval when this Redis hasn't seen the script yet (or
      # has been flushed since).
      def run_script(script, sha, keys, argv)
        @redis.evalsha(sha, keys: keys, argv: argv)
      rescue Redis::CommandError => e
        raise unless e.message.include?("NOSCRIPT")

        @redis.eval(script, keys: keys, argv: argv)
      end

      def bucket_args(key)
        keys       = ["#{@namespace}:#{key}:minute"]
        capacities = [@per_minute]
        windows    = [MINUTE_MS]

        if @per_day
          keys       << "#{@namespace}:#{key}:day"
          capacities << @per_day
          windows    << DAY_MS
        end

        [keys, capacities, windows]
      end

      def log_redis_failure(error)
        message = "[xero-kiwi] throttle limiter Redis error (failing open): #{error.class}: #{error.message}"
        if @logger
          @logger.warn(message)
        else
          Kernel.warn(message)
        end
      end
    end
  end
end
