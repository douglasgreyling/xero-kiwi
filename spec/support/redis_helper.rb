# frozen_string_literal: true

require "redis"

# Lua-backed specs need a real Redis. mock_redis doesn't execute Lua, and a
# Ruby port would just be a second implementation to maintain. The helper
# returns a connected client or nil — specs use `skip` when nil, so CI
# without Redis stays green and local developers get full coverage when
# they boot one.
module RedisSpecHelper
  URL = ENV.fetch("TEST_REDIS_URL", "redis://127.0.0.1:6379/15")

  def self.client
    return @client if defined?(@client)

    @client = Redis.new(url: URL, timeout: 0.2, reconnect_attempts: 0).tap(&:ping)
  rescue Redis::BaseError
    @client = nil
  end

  def self.available?
    !client.nil?
  end

  def self.reset!
    client&.flushdb
  end
end
