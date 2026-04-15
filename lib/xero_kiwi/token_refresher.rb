# frozen_string_literal: true

require "uri"

module XeroKiwi
  # Talks to Xero's OAuth2 token endpoint to exchange a refresh token for a
  # fresh access/refresh pair. Lives separately from Client because:
  #
  # - It hits a different host (identity.xero.com, not api.xero.com)
  # - It uses HTTP Basic auth instead of bearer auth
  # - It's stateless — Client owns the token state and asks Refresher to do
  #   the network round-trip
  #
  # See: https://developer.xero.com/documentation/guides/oauth2/auth-flow#refreshing-access-and-refresh-tokens
  class TokenRefresher
    def initialize(client_id:, client_secret:, adapter: nil)
      @client_id     = client_id
      @client_secret = client_secret
      @adapter       = adapter
    end

    # Performs the refresh round-trip and returns a fresh XeroKiwi::Token. Raises
    # TokenRefreshError if Xero rejects the refresh (typically: refresh token
    # expired or already rotated, or wrong client credentials).
    def refresh(refresh_token:)
      raise ArgumentError, "refresh_token is required" if refresh_token.nil? || refresh_token.empty?

      requested_at = Time.now
      response     = post_refresh(refresh_token)
      Token.from_oauth_response(response.body, requested_at: requested_at)
    rescue AuthenticationError, ClientError => e
      raise TokenRefreshError.new(e.status, e.body)
    end

    private

    def post_refresh(refresh_token)
      http.post(Identity::TOKEN_PATH) do |req|
        req.headers["Authorization"] = Identity.basic_auth_header(@client_id, @client_secret)
        req.headers["Content-Type"]  = "application/x-www-form-urlencoded"
        req.headers["Accept"]        = "application/json"
        req.body                     = URI.encode_www_form(
          grant_type:    "refresh_token",
          refresh_token: refresh_token
        )
      end
    end

    def http
      @_http ||= Identity.build_http(adapter: @adapter)
    end
  end
end
