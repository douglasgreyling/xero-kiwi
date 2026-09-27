# frozen_string_literal: true

RSpec.describe XeroKiwi::Throttle::RedisTokenBucket do
  # Stubbed clock + sleeper keep Lua-backed specs fast and deterministic. The
  # bucket reads `now_ms` and sleeps via injected callables, so we advance
  # time manually and assert on sleep calls without any real delay.
  let(:clock)  { -> { @now_ms ||= 1_700_000_000_000 } }
  let(:sleeps) { [] }
  let(:sleeper) do
    ->(seconds) {
      sleeps << seconds
      @now_ms += (seconds * 1000).to_i
    }
  end

  context "with a reachable Redis (Lua-backed algorithm)", :redis do
    before { RedisSpecHelper.reset! }

    let(:redis) { RedisSpecHelper.client }

    def build_bucket(**overrides)
      described_class.new(
        redis:      redis,
        per_minute: 2,
        max_wait:   60.0,
        clock:      clock,
        sleeper:    sleeper,
        **overrides
      )
    end

    describe "#acquire" do
      it "grants the first N calls within the minute window without sleeping" do
        bucket = build_bucket
        2.times { bucket.acquire("tenant-A") }

        expect(sleeps).to be_empty
      end

      it "blocks (sleeps) when the minute bucket is empty, then grants after refill" do
        bucket = build_bucket
        2.times { bucket.acquire("tenant-A") }

        bucket.acquire("tenant-A")

        expect(sleeps.size).to eq(1)
        expect(sleeps.first).to be > 0
      end

      it "raises Throttle::Timeout when per-minute wait exceeds max_wait" do
        tight_bucket = build_bucket(max_wait: 0.001)
        2.times { tight_bucket.acquire("tenant-A") }

        expect { tight_bucket.acquire("tenant-A") }
          .to raise_error(XeroKiwi::Throttle::Timeout, /max_wait=0.001s/)
      end

      it "isolates buckets per tenant key" do
        bucket = build_bucket
        2.times { bucket.acquire("tenant-A") }

        bucket.acquire("tenant-B")

        expect(sleeps).to be_empty
      end

      context "with a per_day limit" do
        it "raises DailyLimitExhausted (no sleep) when the day bucket is empty" do
          bucket = build_bucket(per_day: 3)

          2.times { bucket.acquire("tenant-A") }
          @now_ms += 60_000
          bucket.acquire("tenant-A")
          @now_ms += 60_000

          expect { bucket.acquire("tenant-A") }
            .to raise_error(XeroKiwi::Throttle::DailyLimitExhausted) do |error|
              expect(error.retry_after).to be > 0
            end
        end

        it "rolls back: a day-bucket failure does not decrement the minute bucket" do
          bucket = build_bucket(per_day: 3)

          2.times { bucket.acquire("tenant-A") }
          @now_ms += 60_000
          bucket.acquire("tenant-A")
          @now_ms += 60_000

          minute_before = redis.hget("xero_kiwi:throttle:tenant-A:minute", "tokens").to_f

          expect { bucket.acquire("tenant-A") }.to raise_error(XeroKiwi::Throttle::DailyLimitExhausted)

          minute_after = redis.hget("xero_kiwi:throttle:tenant-A:minute", "tokens").to_f

          # Refill between attempts means `after` may be higher than `before`,
          # but the failed attempt must never have burned a token. Allow a
          # small floating-point margin for the refill math.
          expect(minute_after).to be >= (minute_before - 0.0001)
        end
      end

      it "raises ArgumentError on blank keys" do
        bucket = build_bucket
        expect { bucket.acquire(nil) }.to raise_error(ArgumentError)
        expect { bucket.acquire("") }.to raise_error(ArgumentError)
      end
    end

    describe "#remaining" do
      it "reports a full bucket before anything has been spent" do
        expect(build_bucket.remaining("tenant-A")).to eq(minute: 2, day: nil)
      end

      it "reflects tokens already spent" do
        bucket = build_bucket
        bucket.acquire("tenant-A")

        expect(bucket.remaining("tenant-A")[:minute]).to eq(1)
      end

      # The whole point of a separate script: asking how much is left must
      # not itself cost a token, or a polling caller would starve its own
      # bucket just by looking at it.
      it "commits no decrement of its own" do
        bucket = build_bucket
        5.times { bucket.remaining("tenant-A") }

        expect(bucket.remaining("tenant-A")[:minute]).to eq(2)
      end

      it "reports the day bucket when one is configured" do
        bucket = build_bucket(per_day: 100)

        expect(bucket.remaining("tenant-A")).to eq(minute: 2, day: 100)
      end

      it "keeps tenants apart" do
        bucket = build_bucket
        bucket.acquire("tenant-A")

        expect(bucket.remaining("tenant-B")[:minute]).to eq(2)
      end

      it "rejects a blank key" do
        expect { build_bucket.remaining("") }.to raise_error(ArgumentError)
      end
    end

    # Both throttle errors name the tenant they relate to, so a caller
    # recording a durable back-off signal doesn't have to infer it from
    # surrounding context.
    describe "exception context" do
      it "names the tenant and the wait on DailyLimitExhausted", :aggregate_failures do
        bucket = build_bucket(per_day: 1)
        bucket.acquire("tenant-A")

        expect { bucket.acquire("tenant-A") }.to raise_error(XeroKiwi::Throttle::DailyLimitExhausted) { |error|
          expect(error.tenant_id).to eq("tenant-A")
          expect(error.retry_after).to be > 0
        }
      end

      it "names the tenant and the wait on Timeout", :aggregate_failures do
        bucket = build_bucket(max_wait: 0.0)
        2.times { bucket.acquire("tenant-B") }

        expect { bucket.acquire("tenant-B") }.to raise_error(XeroKiwi::Throttle::Timeout) { |error|
          expect(error.tenant_id).to eq("tenant-B")
          expect(error.retry_after).to be > 0
        }
      end
    end
  end

  context "when Redis raises (fail-open path)" do
    # The fail-open path doesn't need Lua or a live Redis — we only need to
    # confirm that Redis errors short-circuit to a warning. Pure mocks are
    # enough and keep this spec hermetic.
    let(:failing_redis) do
      instance_double(Redis).tap do |r|
        allow(r).to receive(:evalsha).and_raise(Redis::CannotConnectError.new("refused"))
        allow(r).to receive(:eval).and_raise(Redis::CannotConnectError.new("refused"))
      end
    end

    def build_bucket(**overrides)
      described_class.new(
        redis:      failing_redis,
        per_minute: 2,
        max_wait:   60.0,
        clock:      clock,
        sleeper:    sleeper,
        **overrides
      )
    end

    it "fails open and emits a warning via Kernel.warn by default" do
      allow(Kernel).to receive(:warn)

      expect { build_bucket.acquire("tenant-A") }.not_to raise_error
      expect(Kernel).to have_received(:warn).with(/throttle limiter Redis error/)
    end

    it "routes warnings to a custom logger when provided" do
      logger = instance_double(Logger, warn: nil)

      build_bucket(logger: logger).acquire("tenant-A")

      expect(logger).to have_received(:warn).with(/throttle limiter Redis error/)
    end
  end

  describe "initialization" do
    def redis_stub = instance_double(Redis)

    it "rejects non-positive per_minute" do
      expect { described_class.new(redis: redis_stub, per_minute: 0) }.to raise_error(ArgumentError)
    end

    it "rejects non-positive per_day when provided" do
      expect { described_class.new(redis: redis_stub, per_minute: 1, per_day: 0) }.to raise_error(ArgumentError)
    end
  end
end
