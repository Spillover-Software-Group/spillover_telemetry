# frozen_string_literal: true

require "test_helper"
require "support/transactional"

class SolidQueueCollectorTest < ActiveSupport::TestCase
  include Transactional

  test "counts the jobs waiting to run" do
    enqueue

    assert_equal 1, values["QueueDepth"]
  end

  test "reports the age of the oldest job waiting to run" do
    now = Time.now.utc
    enqueue(created_at: now - 90)

    assert_equal 90, values(now)["OldestReadyJobAge"]
  end

  test "reports no age where nothing is waiting to run" do
    assert_nil values["OldestReadyJobAge"]
  end

  test "counts the jobs that have given up" do
    SolidQueue::FailedExecution.create!(job: enqueue, error: "went wrong")

    assert_equal 1, values["FailedJobs"]
  end

  test "reports how long ago this host's supervisor last beat" do
    now = Time.now.utc
    supervise(last_heartbeat_at: now - 12)

    assert_equal 12, values(now)["SupervisorHeartbeatAge"]
  end

  # A forking supervisor records its kind as "Supervisor(fork)", so a supervisor is found as the
  # process with no supervisor of its own rather than by that string.
  test "reads the heartbeat of a forking supervisor" do
    now = Time.now.utc
    supervise(kind: "Supervisor(fork)", last_heartbeat_at: now - 3)

    assert_equal 3, values(now)["SupervisorHeartbeatAge"]
  end

  test "ignores a supervisor beating on another host" do
    supervise(hostname: "another-host")

    assert_nil values["SupervisorHeartbeatAge"]
  end

  test "ignores a worker, which beats under a supervisor of its own" do
    now = Time.now.utc
    supervisor = supervise(last_heartbeat_at: now - 30)
    supervise(kind: "Worker", supervisor_id: supervisor.id, last_heartbeat_at: now)

    assert_equal 30, values(now)["SupervisorHeartbeatAge"]
  end

  private
    def values(now = Time.now.utc)
      SpilloverTelemetry::Metrics::SolidQueueCollector.new.values(now)
    end

    # Creating the job is enough: Solid Queue makes the ready execution itself, in an after_create.
    def enqueue(created_at: Time.now.utc)
      SolidQueue::Job.create!(queue_name: "default", class_name: "SomeJob").tap do |job|
        job.ready_execution.update!(created_at: created_at)
      end
    end

    def supervise(kind: "Supervisor", hostname: Socket.gethostname, supervisor_id: nil,
                  last_heartbeat_at: Time.now.utc)
      SolidQueue::Process.create!(kind: kind, name: "#{kind}-#{SecureRandom.hex(4)}", hostname: hostname,
                                  supervisor_id: supervisor_id, pid: 1, last_heartbeat_at: last_heartbeat_at)
    end
end
