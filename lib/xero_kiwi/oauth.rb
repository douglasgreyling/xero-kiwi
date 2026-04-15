# frozen_string_literal: true

require "openssl"
require "securerandom"
require "uri"

module XeroKiwi
  # Implements the Xero OAuth2 Authorization Code flow. Stateless: each call
  # is a pure function over its arguments, so the same OAuth instance can
  # serve both halves of the redirect (authorise → callback) even when those
  # halves run in different processes.
  #
  # The caller owns session storage for `state` (CSRF) and the PKCE
  # `code_verifier` — XeroKiwi gives you helpers to generate them but doesn't
  # touch your session/cookies/Redis.
  #
  #   oauth = XeroKiwi::OAuth.new(
  #     client_id:     ENV["XERO_CLIENT_ID"],
  #     client_secret: ENV["XERO_CLIENT_SECRET"],
  #     redirect_uri:  "https://app.example.com/xero/callback"
  #   )
  #
  #   # Step 1: kick off authorisation
  #   state = XeroKiwi::OAuth.generate_state
  #   pkce  = XeroKiwi::OAuth.generate_pkce
  #   session[:xero_state]    = state
  #   session[:xero_verifier] = pkce.verifier
  #
  #   redirect_to oauth.authorization_url(
  #     scopes: %w[openid profile email accounting.transactions offline_access],
  #     state:  state,
  #     pkce:   pkce
  #   )
  #
  #   # Step 2: callback
  #   XeroKiwi::OAuth.verify_state!(
  #     received: params[:state],
  #     expected: session.delete(:xero_state)
  #   )
  #   token = oauth.exchange_code(
  #     code:          params[:code],
  #     code_verifier: session.delete(:xero_verifier)
  #   )
  #
  # See: https://developer.xero.com/documentation/guides/oauth2/auth-flow
  class OAuth
    # CSRF protection failure: the state value Xero echoed back didn't match
    # the one we stashed before the redirect. Indicates a forged callback or
    # a session that was lost between request and response.
    class StateMismatchError < XeroKiwi::Error; end

    # Raised when the auth code can't be exchanged for tokens (invalid_grant,
    # expired code, wrong redirect_uri, missing PKCE verifier, etc). Caller
    # should restart the OAuth flow from the authorise step.
    class CodeExchangeError < AuthenticationError; end

    # Raised when an id_token JWT can't be verified — bad signature, wrong
    # issuer/audience, expired, or nonce mismatch.
    class IDTokenError < XeroKiwi::Error; end

    JWKS_CACHE_TTL = 3600

    attr_reader :client_id, :client_secret, :redirect_uri

    # Generates a cryptographically random `state` value for CSRF protection.
    # Caller stashes this somewhere request-scoped (session, signed cookie)
    # before redirecting and verifies it on callback.
    def self.generate_state(byte_length: 32)
      SecureRandom.urlsafe_base64(byte_length)
    end

    # Generates a fresh PKCE verifier+challenge pair.
    def self.generate_pkce
      PKCE.generate
    end

    # Constant-time comparison of the state Xero echoed back vs the value we
    # stashed. Raises StateMismatchError on any mismatch — including nil
    # values, length mismatches, or content mismatches. The length check up
    # front is required because OpenSSL.fixed_length_secure_compare raises
    # ArgumentError on unequal-length input.
    def self.verify_state!(received:, expected:)
      raise StateMismatchError, "OAuth state parameter mismatch" if state_mismatch?(received, expected)
    end

    def self.state_mismatch?(received, expected)
      return true if received.nil? || expected.nil?
      return true if received.bytesize != expected.bytesize

      !OpenSSL.fixed_length_secure_compare(received, expected)
    end
    private_class_method :state_mismatch?

    # `redirect_uri:` is required for the auth-code flow itself
    # (`authorization_url` and `exchange_code`) but not for `revoke_token`
    # or `verify_id_token`. It's optional at construction time so callers
    # who only need the latter operations don't have to invent a fake URL.
    def initialize(client_id:, client_secret:, redirect_uri: nil, adapter: nil)
      @client_id       = client_id
      @client_secret   = client_secret
      @redirect_uri    = redirect_uri
      @adapter         = adapter
      @jwks_mutex      = Mutex.new
      @jwks_cache      = nil
      @jwks_fetched_at = nil
    end

    # Builds the authorisation URL the caller redirects the user to. The
    # returned URL is opaque — the caller's job is just to redirect to it.
    #
    # `state` is required (CSRF). `pkce` is optional but recommended; pass a
    # XeroKiwi::OAuth::PKCE instance and you'll need to supply the matching
    # `code_verifier:` at exchange time.
    def authorization_url(scopes:, state:, pkce: nil, nonce: nil)
      raise ArgumentError, "redirect_uri was not configured at construction time" if redirect_uri.nil?
      raise ArgumentError, "scopes cannot be empty" if Array(scopes).empty?
      raise ArgumentError, "state is required"      if state.nil? || state.empty?

      "#{Identity::AUTHORIZE_URL}?#{URI.encode_www_form(authorize_params(scopes, state, pkce, nonce))}"
    end

    # Exchanges an authorisation code for a XeroKiwi::Token. Pass the same
    # `code_verifier` you used to build the authorisation URL — or omit it
    # if you didn't use PKCE.
    def exchange_code(code:, code_verifier: nil)
      raise ArgumentError, "redirect_uri was not configured at construction time" if redirect_uri.nil?
      raise ArgumentError, "code is required" if code.nil? || code.empty?

      requested_at = Time.now
      response     = post_token_exchange(code, code_verifier)
      Token.from_oauth_response(response.body, requested_at: requested_at)
    rescue AuthenticationError, ClientError => e
      raise CodeExchangeError.new(e.status, e.body)
    end

    # Revokes a refresh token at Xero's revocation endpoint (RFC 7009).
    # Revoking the refresh token also invalidates every access token that
    # was issued from it, so this is the right call to clean up after
    # "disconnect Xero" / logout flows.
    #
    # Pass the *refresh* token, not the access token. Per RFC 7009 the
    # endpoint accepts either, but Xero only invalidates the chain when
    # you revoke the refresh token — passing an access token leaves the
    # refresh token alive, which is almost never what you want.
    def revoke_token(refresh_token:)
      raise ArgumentError, "refresh_token is required" if refresh_token.nil? || refresh_token.empty?

      http.post(Identity::REVOKE_PATH) do |req|
        req.headers["Authorization"] = Identity.basic_auth_header(client_id, client_secret)
        req.headers["Content-Type"]  = "application/x-www-form-urlencoded"
        req.body                     = URI.encode_www_form(
          token:           refresh_token,
          token_type_hint: "refresh_token"
        )
      end
      true
    end

    # Verifies an OIDC id_token JWT using this OAuth instance's client_id as
    # the audience. Uses the instance-level JWKS cache so repeated
    # verifications don't refetch Xero's signing keys for every callback.
    def verify_id_token(id_token, nonce: nil)
      IDToken.verify(
        id_token,
        client_id: client_id,
        nonce:     nonce,
        jwks:      -> { cached_jwks }
      )
    end

    private

    def authorize_params(scopes, state, pkce, nonce)
      params         = {
        response_type: "code",
        client_id:     client_id,
        redirect_uri:  redirect_uri,
        scope:         Array(scopes).join(" "),
        state:         state
      }
      params[:nonce] = nonce if nonce
      if pkce
        params[:code_challenge]        = pkce.challenge
        params[:code_challenge_method] = PKCE::CHALLENGE_METHOD
      end
      params
    end

    def post_token_exchange(code, code_verifier)
      http.post(Identity::TOKEN_PATH) do |req|
        req.headers["Authorization"] = Identity.basic_auth_header(client_id, client_secret)
        req.headers["Content-Type"]  = "application/x-www-form-urlencoded"
        req.headers["Accept"]        = "application/json"
        req.body                     = URI.encode_www_form(token_exchange_body(code, code_verifier))
      end
    end

    def token_exchange_body(code, code_verifier)
      body                 = {
        grant_type:   "authorization_code",
        code:         code,
        redirect_uri: redirect_uri
      }
      body[:code_verifier] = code_verifier if code_verifier
      body
    end

    # In-process JWKS cache. We hold the mutex during the fetch so concurrent
    # callers don't trigger duplicate HTTP requests, and refresh on TTL
    # expiry. If a JWT references a `kid` we don't have, ruby-jwt's JWKS
    # loader will signal that and we could refetch — but for now a 1-hour
    # TTL covers Xero's normal key rotation cadence.
    def cached_jwks
      @jwks_mutex.synchronize do
        if @jwks_cache.nil? || (Time.now - @jwks_fetched_at) > JWKS_CACHE_TTL
          @jwks_cache      = fetch_jwks
          @jwks_fetched_at = Time.now
        end
        @jwks_cache
      end
    end

    def fetch_jwks
      response = http.get(Identity::JWKS_PATH)
      response.body.fetch("keys")
    end

    def http
      @_http ||= Identity.build_http(adapter: @adapter)
    end
  end
end
