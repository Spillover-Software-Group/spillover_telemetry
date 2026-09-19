# frozen_string_literal: true

require "socket"

module SpilloverTelemetry
  class Metrics
    # What the queue of this application looks like: how much is waiting, how long the oldest of it
    # has waited, how much has given up, and whether this host's supervisor is still beating.
    class SolidQueueCollector
      UNITS = {
        "QueueDepth" => "Count",
        "OldestReadyJobAge" => "Seconds",
        "FailedJobs" => "Count",
        "SupervisorHeartbeatAge" => "Seconds"
      }.freeze

      def available?
        Object.const_defined?(:SolidQueue)
      end

      # Checked out for the four queries and given straight back, from the pool Solid Queue's own
      # models use. Active Record hands a connection to the thread that asks and keeps it there
      # until it is released, so the sampler's thread, which lives as long as the process, would
      # hold one of the pool's connections for good and leave the threads doing the work one fewer
      # to share. A suite cannot catch a regression here: transactional fixtures pin one connection
      # across every thread, so a test passes either way.
      def values(now)
        ::SolidQueue::Record.connection_pool.with_connection do
          {
            "QueueDepth" => ::SolidQueue::ReadyExecution.count,
            "OldestReadyJobAge" => seconds_since(::SolidQueue::ReadyExecution.minimum(:created_at), now),
            "FailedJobs" => ::SolidQueue::FailedExecution.count,
            "SupervisorHeartbeatAge" => seconds_since(supervisor_heartbeat, now)
          }
        end
      end

      private
        # The supervisor is the process that has none: its children carry its id. Matching on `kind`
        # instead would have to know that a forking supervisor records itself as "Supervisor(fork)".
        # Narrowed to this host, so a supervisor that died here is not covered for by a live one
        # somewhere else in the same database.
        def supervisor_heartbeat
          ::SolidQueue::Process
            .where(supervisor_id: nil, hostname: Socket.gethostname)
            .maximum(:last_heartbeat_at)
        end

        def seconds_since(time, now)
          (now - time).round if time
        end
    end
  end
end
