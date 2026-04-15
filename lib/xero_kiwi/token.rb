# frozen_string_literal: true

module XeroKiwi
  # Immutable value object representing an OAuth2 token pair, plus the
  # surrounding metadata Xero returns at refresh time (id_token, scope, etc).
  #
  #   token = XeroKiwi::Token.new(
  #     access_token:  "ya29...",
  #     refresh_token: "1//...",
  #     expires_at:    Time.now + 1800
  #   )
  #
  #   token.expired?         # => false
  #   token.expiring_soon?   # => false (default 60s window)
  #   token.refreshable?     # => true
  #
  # Use .from_oauth_response to build a Token from a raw Xero token-endpoint
  # response — it converts Xero's `expires_in` (seconds-from-now) into an
  # absolute `expires_at` Time, anchored at the moment the request was made.
  class Token
    DEFAULT_EXPIRY_WINDOW = 60

    attr_reader :access_token, :refresh_token, :expires_at, :token_type, :id_token, :scope

    def self.from_oauth_response(payload, requested_at: Time.now)
      payload    = payload.transform_keys(&:to_s)
      expires_in = payload["expires_in"]

      new(
        access_token:  payload["access_token"],
        refresh_token: payload["refresh_token"],
        expires_at:    expires_in ? requested_at + expires_in.to_i : nil,
        token_type:    payload["token_type"] || "Bearer",
        id_token:      payload["id_token"],
        scope:         payload["scope"]
      )
    end

    def initialize(access_token:, refresh_token: nil, expires_at: nil,
                   token_type: "Bearer", id_token: nil, scope: nil)
      @access_token  = access_token
      @refresh_token = refresh_token
      @expires_at    = expires_at
      @token_type    = token_type
      @id_token      = id_token
      @scope         = scope
    end

    # True if expires_at is in the past. Returns false when expires_at is
    # unknown — without an expiry we have no signal to act on, so callers
    # should fall through to reactive (on-401) handling.
    def expired?(now: Time.now)
      return false if expires_at.nil?

      now >= expires_at
    end

    # True if the token expires within `within` seconds from `now`. Used by the
    # client to decide whether to refresh proactively before a request. The
    # default 60s window is wide enough to absorb network round-trip races
    # without being so wide that we burn refresh tokens unnecessarily.
    def expiring_soon?(within: DEFAULT_EXPIRY_WINDOW, now: Time.now)
      return false if expires_at.nil?

      now + within >= expires_at
    end

    def valid?(now: Time.now)
      !access_token.nil? && !access_token.empty? && !expired?(now: now)
    end

    def refreshable?
      !refresh_token.nil? && !refresh_token.empty?
    end

    def to_h
      {
        access_token:  access_token,
        refresh_token: refresh_token,
        expires_at:    expires_at,
        token_type:    token_type,
        id_token:      id_token,
        scope:         scope
      }
    end

    def ==(other)
      other.is_a?(Token) && other.to_h == to_h
    end
    alias eql? ==

    def hash = to_h.hash

    def inspect
      "#<#{self.class} access_token=#{access_token && "[FILTERED]"} " \
        "refreshable=#{refreshable?} expires_at=#{expires_at.inspect}>"
    end
  end
end
