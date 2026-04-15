# frozen_string_literal: true

RSpec.describe XeroKiwi::Throttle::Middleware do
  let(:limiter) { instance_double(XeroKiwi::Throttle::NullLimiter, acquire: nil) }

  let(:connection) do
    limiter_instance = limiter
    Faraday.new do |f|
      f.use described_class, limiter_instance
      f.adapter :test do |stub|
        stub.get("/anything") { [200, {}, "ok"] }
      end
    end
  end

  it "calls limiter.acquire with the tenant id from the Xero-Tenant-Id header" do
    connection.get("/anything") { |req| req.headers["Xero-Tenant-Id"] = "tenant-xyz" }

    expect(limiter).to have_received(:acquire).with("tenant-xyz")
  end

  it "skips the limiter when no Xero-Tenant-Id header is present" do
    connection.get("/anything")

    expect(limiter).not_to have_received(:acquire)
  end

  it "skips the limiter when the tenant id is blank" do
    connection.get("/anything") { |req| req.headers["Xero-Tenant-Id"] = "" }

    expect(limiter).not_to have_received(:acquire)
  end

  it "propagates Throttle errors to the caller" do
    allow(limiter).to receive(:acquire).and_raise(XeroKiwi::Throttle::Timeout, "too long")

    expect { connection.get("/anything") { |req| req.headers["Xero-Tenant-Id"] = "t" } }
      .to raise_error(XeroKiwi::Throttle::Timeout)
  end
end
