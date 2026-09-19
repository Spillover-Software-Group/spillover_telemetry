# frozen_string_literal: true

module SpilloverTelemetry
  class Metrics
    # What the web server in this process is doing: how many requests are waiting for a thread, how
    # many threads could still take one, and how many are running.
    class PumaCollector
      UNITS = {
        "PumaBacklog" => "Count",
        "PumaPoolCapacity" => "Count",
        "PumaRunningThreads" => "Count"
      }.freeze

      def initialize
        @stats = read_stats
      end

      # Puma publishes its numbers only once its server is running, and the first sample of a slow
      # boot can land before that. A document short of them is better than no document.
      def available?
        !@stats.nil?
      end

      def values(_now)
        {
          "PumaBacklog" => @stats[:backlog],
          "PumaPoolCapacity" => @stats[:pool_capacity],
          "PumaRunningThreads" => @stats[:running]
        }
      end

      private
        # Puma answers through whichever object claimed the reader when it started, and nothing
        # claims it in a process that never started a server, so there the reader raises rather than
        # answering nothing.
        def read_stats
          ::Puma.stats_hash if Object.const_defined?(:Puma)
        rescue NoMethodError
          nil
        end
    end
  end
end
