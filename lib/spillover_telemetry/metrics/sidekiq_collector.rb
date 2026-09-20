# frozen_string_literal: true

require "socket"

module SpilloverTelemetry
  class Metrics
    # What the queue of a Sidekiq application looks like: how much is waiting, how long the oldest
    # of it has waited, how much has failed, how long ago a process working it last beat, how much
    # is held for later, and how many processes there are.
    #
    # The four it shares with the Solid Queue collector are the four every alarm and dashboard in
    # the platform reads, and they mean here what they mean there, so an application that runs its
    # jobs under Sidekiq is watched by what is already built. No process reports both.
    class SidekiqCollector
      UNITS = {
        "QueueDepth" => "Count",
        "OldestReadyJobAge" => "Seconds",
        "FailedJobs" => "Count",
        "SupervisorHeartbeatAge" => "Seconds",
        "ScheduledJobs" => "Count",
        "Processes" => "Count",
        "BusyWorkers" => "Count"
      }.freeze

      # Requiring Sidekiq does not define the classes below: they are `sidekiq/api`, which only the
      # web UI and the monitor command ask for, and which a process that runs jobs has never needed.
      # Asked for here rather than at load, because a process without Sidekiq has nothing to ask.
      def available?
        return false unless Object.const_defined?(:Sidekiq)

        require "sidekiq/api"
        true
      end

      def values(now)
        stats = ::Sidekiq::Stats.new
        # Enumerated once rather than asked for its `size`, which Sidekiq documents as the count
        # before the processes that stopped beating are taken out of it. Iterating leaves them out.
        processes = ::Sidekiq::ProcessSet.new.to_a

        {
          "QueueDepth" => stats.enqueued,
          "OldestReadyJobAge" => oldest_ready_job_age,
          # What has failed and not yet been dealt with: waiting to be tried again, or out of tries
          # and put aside. Not `Sidekiq::Stats#failed`, which is every job that has ever failed,
          # counted since the Redis it reads was last emptied, so it only climbs and an alarm on it
          # fires once and never clears.
          "FailedJobs" => stats.retry_size + stats.dead_size,
          "SupervisorHeartbeatAge" => heartbeat_age(processes, now),
          "ScheduledJobs" => stats.scheduled_size,
          # Every process against this Redis, not only this host's: how much is working the queue
          # is a fact about the queue, the way its depth is, and both hosts of a pair report it.
          # The heartbeat above is the one number that has to be about this host.
          "Processes" => processes.size,
          "BusyWorkers" => processes.sum { |process| process["busy"] }
        }
      end

      private
        # Sidekiq measures a queue's wait as the age of the job at the back of it, and answers 0 for
        # a queue holding nothing, so a queue with nothing waiting in it is left out rather than
        # reported as one nothing has waited in. The longest of them is the number an alarm wants:
        # a queue nobody is working is what it is there to find.
        def oldest_ready_job_age
          waiting = ::Sidekiq::Queue.all.map(&:latency).reject(&:zero?)

          waiting.max.round if waiting.any?
        end

        # Every Sidekiq process beats for itself, with no supervisor over them to ask, so the
        # newest beat is how long ago this queue was last known to be worked. Narrowed to the host
        # this process runs on, against the name Sidekiq recorded with the beat, so that a role
        # spread over a pair of hosts against one Redis does not have a dead half of it covered for
        # by the live one. Nothing beating here reports no age at all rather than a large one,
        # which is what leaves the alarm to its missing-data rule.
        def heartbeat_age(processes, now)
          here = Socket.gethostname
          newest = processes.filter_map { |process| process["beat"] if process["hostname"] == here }.max

          (now.to_f - newest).round if newest
        end
    end
  end
end
