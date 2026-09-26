# frozen_string_literal: true

module XeroKiwi
  module Throttle
    # Default limiter when no `throttle:` is passed to Client.new. Does nothing
    # — preserves the pre-throttle behaviour where calls go straight out and
    # the retry middleware reacts to any 429s that come back.
    #
    # Also documents the limiter contract: any object implementing
    # `#acquire(key)` can be passed as `throttle:`. `#remaining(key)` is
    # optional — Client checks for it before asking, so a limiter written
    # against the original contract keeps working.
    class NullLimiter
      def acquire(_key)
        nil
      end

      # Nothing is being limited, so there's no quota reading to give.
      def remaining(_key)
        nil
      end
    end
  end
end
