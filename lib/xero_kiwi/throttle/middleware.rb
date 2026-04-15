# frozen_string_literal: true

require "faraday"

module XeroKiwi
  module Throttle
    # Faraday request middleware. On every outbound call it reads the
    # `Xero-Tenant-Id` header and asks the limiter for a token. Requests
    # without a tenant header (e.g. `/connections`, OAuth endpoints) pass
    # straight through — they have no tenant bucket to check.
    #
    # Placement matters: this sits *below* faraday-retry in the stack, so
    # every retry attempt also re-enters the limiter and consumes a token.
    class Middleware < Faraday::Middleware
      TENANT_HEADER = "Xero-Tenant-Id"

      def initialize(app, limiter)
        super(app)
        @limiter = limiter
      end

      def on_request(env)
        tenant_id = env.request_headers[TENANT_HEADER]
        return if tenant_id.nil? || tenant_id.empty?

        @limiter.acquire(tenant_id)
      end
    end
  end
end
