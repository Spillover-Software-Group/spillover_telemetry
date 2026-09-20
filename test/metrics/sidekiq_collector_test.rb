# frozen_string_literal: true

require "test_helper"
require "support/sidekiq_runtime"

class SidekiqCollectorTest < ActiveSupport::TestCase
  include SidekiqRuntime

  test "counts the jobs waiting to run" do
    run_sidekiq(enqueued: 3)

    assert_equal 3, values["QueueDepth"]
  end

  test "reports the longest a job has waited in any queue" do
    run_sidekiq(latencies: [ 12.5, 90.4 ])

    assert_equal 90, values["OldestReadyJobAge"]
  end

  # Sidekiq gives a queue holding nothing a wait of 0, which is a queue keeping up rather than one
  # a job has waited no time at all in.
  test "reports no wait where every queue is empty" do
    run_sidekiq(latencies: [ 0, 0 ])

    assert_nil values["OldestReadyJobAge"]
  end

  test "reports no wait where there is no queue" do
    run_sidekiq

    assert_nil values["OldestReadyJobAge"]
  end

  # What has failed and not been dealt with, rather than Sidekiq's count of every job that ever
  # failed, which only climbs.
  test "counts the jobs waiting to be tried again together with those out of tries" do
    run_sidekiq(retrying: 2, dead: 5)

    assert_equal 7, values["FailedJobs"]
  end

  test "reports how long ago a process last beat" do
    now = Time.now.utc

    run_sidekiq(processes: [ beating(now - 12) ])

    assert_equal 12, values(now)["SupervisorHeartbeatAge"]
  end

  test "reports the newest beat of the processes working the queue" do
    now = Time.now.utc

    run_sidekiq(processes: [ beating(now - 30), beating(now - 3) ])

    assert_equal 3, values(now)["SupervisorHeartbeatAge"]
  end

  # Nothing beating is left to the alarm's missing-data rule rather than reported as an age.
  test "reports no heartbeat where no process is working the queue" do
    run_sidekiq

    assert_nil values["SupervisorHeartbeatAge"]
  end

  # The job role runs on both hosts of a pair against one Redis, and a dead half of it must not be
  # covered for by the live one.
  test "ignores a process beating on another host" do
    run_sidekiq(processes: [ beating(hostname: "another-host") ])

    assert_nil values["SupervisorHeartbeatAge"]
  end

  test "reports this host's beat where another host beat more recently" do
    now = Time.now.utc

    run_sidekiq(processes: [ beating(now - 40), beating(now - 5, hostname: "another-host") ])

    assert_equal 40, values(now)["SupervisorHeartbeatAge"]
  end

  test "counts the jobs held to run later" do
    run_sidekiq(scheduled: 4)

    assert_equal 4, values["ScheduledJobs"]
  end

  # How much is working the queue is a fact about the queue, like its depth, so it is counted
  # across the hosts rather than narrowed to this one the way the heartbeat is.
  test "counts the processes working the queue on every host" do
    run_sidekiq(processes: [ beating, beating(hostname: "another-host") ])

    assert_equal 2, values["Processes"]
  end

  test "counts the threads those processes are busy in" do
    run_sidekiq(processes: [ beating(busy: 0), beating(busy: 3, hostname: "another-host") ])

    assert_equal 3, values["BusyWorkers"]
  end

  test "reports nothing where Sidekiq is not in this process" do
    assert_not_predicate SpilloverTelemetry::Metrics::SidekiqCollector.new, :available?
  end

  private
    # Read the way the registry reads a collector: what it can see, and then what it says. The
    # first of those is what loads Sidekiq's read side, so the order is the collector's contract
    # rather than this helper's convenience.
    def values(now = Time.now.utc)
      collector = SpilloverTelemetry::Metrics::SidekiqCollector.new
      return {} unless collector.available?

      collector.values(now)
    end

    # One entry of the process set, as Sidekiq yields it. A process records the host it runs on
    # with its beat, and here that is this one unless a test says otherwise.
    def beating(at = Time.now.utc, busy: 0, hostname: Socket.gethostname)
      { "busy" => busy, "beat" => at.to_f, "hostname" => hostname }
    end
end
