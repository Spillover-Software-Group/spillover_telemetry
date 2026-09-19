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

  private
    def collector
      SpilloverTelemetry::Metrics::PumaCollector.new
    end

    def values
      collector.values(Time.now.utc)
    end
end
