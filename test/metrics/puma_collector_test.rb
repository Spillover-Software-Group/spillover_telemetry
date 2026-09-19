# frozen_string_literal: true

require "test_helper"
require "support/puma_server"

class PumaCollectorTest < ActiveSupport::TestCase
  include PumaServer

  test "reports the pool of the server running in this process" do
    start_puma_server

    assert_equal [ 0, 5, 0 ], values.values_at("PumaBacklog", "PumaPoolCapacity", "PumaRunningThreads")
  end

  # Which is also the state of the first sample of a slow boot, before the server is listening.
  test "reports nothing where no server is running in this process" do
    assert_not_predicate collector, :available?
  end

  # In cluster mode the sampling process is the master, whose stats carry one status per worker.
  test "sums the pools of a cluster's workers" do
    claim_cluster_stats(
      { last_status: { backlog: 2, running: 5, pool_capacity: 0 } },
      { last_status: { backlog: 0, running: 3, pool_capacity: 2 } }
    )

    assert_equal [ 2, 2, 8 ], values.values_at("PumaBacklog", "PumaPoolCapacity", "PumaRunningThreads")
  end

  test "counts a worker that has not booted for nothing rather than for zero" do
    claim_cluster_stats({ last_status: { backlog: 1, running: 5, pool_capacity: 4 } }, { last_status: {} })

    assert_equal [ 1, 4, 5 ], values.values_at("PumaBacklog", "PumaPoolCapacity", "PumaRunningThreads")
  end

  test "reports a cluster whose workers are all still booting as short of its numbers" do
    claim_cluster_stats({ last_status: {} })

    assert_predicate collector, :available?
    assert_empty values.compact
  end

  private
    def collector
      SpilloverTelemetry::Metrics::PumaCollector.new
    end

    def values
      collector.values(Time.now.utc)
    end

    # What Puma::Cluster#stats answers in the master, with only the per-worker status this test is
    # about; the reader is given back by PumaServer#after_teardown.
    def claim_cluster_stats(*workers)
      stats = { workers: workers.size, booted_workers: workers.size, worker_status: workers }
      ::Puma.stats_object = Struct.new(:stats).new(stats)
    end
end
