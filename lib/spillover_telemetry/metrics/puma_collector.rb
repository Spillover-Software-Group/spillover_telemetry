# frozen_string_literal: true

module SpilloverTelemetry
  class Metrics
    # What the web server in this process is doing: how many requests are waiting for a thread, how
    # many threads could still take one, and how many are running.
    #
    # In single mode the process is the server and Puma answers with its own pool. In cluster mode
    # the process that samples is the master (the application initialises once, before the fork, and
    # a thread does not survive one), and the master answers with a status per worker instead; the
    # numbers are then the sum over the workers, which is what a container-wide alarm wants: the
    # backlog is every request waiting on this host, and the capacity is every thread that could
    # take one.
    class PumaCollector
      UNITS = {
        "PumaBacklog" => "Count",
        "PumaPoolCapacity" => "Count",
        "PumaRunningThreads" => "Count"
      }.freeze

      POOL_KEYS = { "PumaBacklog" => :backlog, "PumaPoolCapacity" => :pool_capacity, "PumaRunningThreads" => :running }.freeze

      def initialize
        @stats = read_stats
      end

      # Puma publishes its numbers only once its server is running, and the first sample of a slow
      # boot can land before that. A document short of them is better than no document.
      def available?
        !@stats.nil?
      end

      def values(_now)
        pools = @stats.key?(:worker_status) ? booted_worker_pools : [ @stats ]

        POOL_KEYS.transform_values do |key|
          measured = pools.filter_map { |pool| pool[key] }
          measured.sum if measured.any?
        end
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

        # A worker reports its pool to the master once it has booted; before that its status is
        # empty, and it counts for nothing rather than for zero.
        def booted_worker_pools
          @stats[:worker_status].filter_map { |worker| worker[:last_status] }.reject(&:empty?)
        end
    end
  end
end
