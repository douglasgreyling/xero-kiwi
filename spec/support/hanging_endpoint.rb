# frozen_string_literal: true

require "socket"

module HangingEndpoint
  HOST    = "127.0.0.1"
  TIMEOUT = 0.3
  GRACE   = 0.25
end

# The kernel completes the handshake without `accept`, so only a read timeout
# ends the request.
RSpec.shared_context "with a hanging endpoint" do
  let(:hanging_server) { TCPServer.new(HangingEndpoint::HOST, 0) }
  let(:hanging_url)    { "http://#{HangingEndpoint::HOST}:#{hanging_server.addr[1]}" }

  around { |example| VCR.turned_off { example.run } }

  after { hanging_server.close }
end

RSpec::Matchers.define :time_out_with do |error_class|
  supports_block_expectations

  chain(:after) { |seconds| @seconds = seconds }

  match do |block|
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      block.call
    rescue error_class
      @raised = true
    end
    @elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    @raised && @elapsed >= @seconds && @elapsed < @seconds + HangingEndpoint::GRACE
  end

  failure_message do
    if @raised
      "expected #{error_class} after #{@seconds}s, but it took #{@elapsed.round(2)}s"
    else
      "expected #{error_class} after #{@seconds}s, but nothing was raised"
    end
  end
end
