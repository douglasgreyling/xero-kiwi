# frozen_string_literal: true

require "base64"
require "faraday"

module XeroKiwi
  # Internal helpers for talking to Xero's identity infrastructure (the OAuth
  # authorisation server at login.xero.com and the token/JWKS endpoints at
  # identity.xero.com). Used by both XeroKiwi::TokenRefresher and XeroKiwi::OAuth —
  # they POST to the same /connect/token endpoint with the same Basic auth
  # header, just different grant types.
  module Identity
    URL              = "https://identity.xero.com"
    AUTHORIZE_URL    = "https://login.xero.com/identity/connect/authorize"
    TOKEN_PATH       = "/connect/token"
    REVOKE_PATH      = "/connect/revocation"
    JWKS_PATH        = "/.well-known/openid-configuration/jwks"
    JWKS_URL         = "#{URL}#{JWKS_PATH}".freeze

    module_function

    # Builds a Faraday connection configured for the Xero identity host:
    # JSON response parsing and our exception mapping. No retry middleware
    # — token endpoints aren't subject to the same rate limits as the API,
    # and retrying a failed token call usually masks a real configuration
    # problem instead of fixing a transient one.
    def build_http(adapter: nil)
      Faraday.new(url: URL) do |f|
        f.use Client::ResponseHandler
        f.response :json, content_type: /\bjson/
        f.adapter(adapter || Faraday.default_adapter)
      end
    end

    def basic_auth_header(client_id, client_secret)
      encoded = Base64.strict_encode64("#{client_id}:#{client_secret}")
      "Basic #{encoded}"
    end
  end
end
