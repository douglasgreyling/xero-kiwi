# frozen_string_literal: true

RSpec.describe XeroKiwi::RateLimit do
  subject(:rate_limit) { described_class.new(reported: reported, configured: configured) }

  let(:reported)   { nil }
  let(:configured) { nil }

  def reported_with(day:, minute: 55)
    XeroKiwi::RateLimit::Reported.new(day: day, minute: minute, app_minute: nil)
  end

  def configured_with(day:, minute: 55)
    XeroKiwi::RateLimit::Configured.new(day: day, minute: minute)
  end

  describe "#day_remaining" do
    context "when only Xero has reported" do
      let(:reported) { reported_with(day: 3_000) }

      it "uses the reported figure" do
        expect(rate_limit.day_remaining).to eq(3_000)
      end
    end

    context "when only the throttle bucket has a reading" do
      let(:configured) { configured_with(day: 500) }

      it "uses the bucket figure" do
        expect(rate_limit.day_remaining).to eq(500)
      end
    end

    # The configured limit is headroom chosen on purpose. Xero reporting more
    # left than the bucket holds must not let a sync spend past it.
    context "when the configured bucket is the stricter of the two" do
      let(:reported)   { reported_with(day: 3_000) }
      let(:configured) { configured_with(day: 500) }

      it "takes the bucket figure and names it as binding", :aggregate_failures do
        expect(rate_limit.day_remaining).to eq(500)
        expect(rate_limit.day_source).to eq(:configured)
      end
    end

    # The mirror case: another application on the same tenant has burned the
    # quota, so our own bucket's view is optimistic and Xero's wins.
    context "when Xero reports less than the bucket holds" do
      let(:reported)   { reported_with(day: 50) }
      let(:configured) { configured_with(day: 2_000) }

      it "takes the reported figure and names it as binding", :aggregate_failures do
        expect(rate_limit.day_remaining).to eq(50)
        expect(rate_limit.day_source).to eq(:reported)
      end
    end

    context "when neither source has a reading" do
      it "reports nothing known", :aggregate_failures do
        expect(rate_limit.day_remaining).to be_nil
        expect(rate_limit.day_source).to be_nil
        expect(rate_limit.known?).to be(false)
      end
    end
  end

  describe "#minute_remaining" do
    let(:reported)   { reported_with(day: 4_000, minute: 10) }
    let(:configured) { configured_with(day: 4_000, minute: 55) }

    it "takes the stricter minute figure independently of the day figure", :aggregate_failures do
      expect(rate_limit.minute_remaining).to eq(10)
      expect(rate_limit.minute_source).to eq(:reported)
    end
  end

  describe "#day_below?" do
    context "with a reading above the threshold" do
      let(:configured) { configured_with(day: 2_000) }

      it "is false" do
        expect(rate_limit.day_below?(1_000)).to be(false)
      end
    end

    context "with a reading below the threshold" do
      let(:configured) { configured_with(day: 999) }

      it "is true" do
        expect(rate_limit.day_below?(1_000)).to be(true)
      end
    end

    # Not knowing how much quota is left is not a reason to halt a sync — and
    # halting here would break the common case, where the first call is what
    # populates the reported figures in the first place.
    context "with nothing known" do
      it "is false rather than assuming the worst" do
        expect(rate_limit.day_below?(1_000)).to be(false)
      end
    end
  end

  describe "#minute_below?" do
    let(:reported) { reported_with(day: 4_000, minute: 3) }

    it "compares against the minute reading" do
      expect(rate_limit.minute_below?(5)).to be(true)
    end
  end

  describe "#inspect" do
    let(:reported)   { reported_with(day: 3_000) }
    let(:configured) { configured_with(day: 500) }

    it "shows the binding number and which source bound it" do
      expect(rate_limit.inspect).to include("day_remaining=500", ":configured")
    end
  end
end
