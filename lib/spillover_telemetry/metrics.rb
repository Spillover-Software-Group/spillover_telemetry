# frozen_string_literal: true

require "json"

require_relative "metrics/puma_collector"
require_relative "metrics/solid_queue_collector"

module SpilloverTelemetry
  # One CloudWatch Embedded Metric Format document a minute on stdout. The log driver already ships
  # stdout, and CloudWatch reads the fields named under `_aws` as metrics, so this needs no agent, no
  # SDK and no sidecar.
  #
  # The document has to be the whole line, which is why it is written straight to the stream rather
  # than through a logger: a logger would bury it inside a message field.
  #
  # A process reports what it is: a server reports Puma's numbers, a Solid Queue supervisor reports
  # the queue's, and a server running the queue inside itself reports both. The caller says which,
  # because a number reported by two processes on one host is a number nobody can read.
  class Metrics
    INTERVAL = 60

    # The name a process asks for, and the class that answers it. A new runtime is a collector
    # beside these two and a line here; nothing else knows the names.
    COLLECTORS = {
      puma: PumaCollector,
      solid_queue: SolidQueueCollector
    }.freeze

    # Every metric any collector can report, with its unit. CloudWatch takes the unit from the
    # document, so a name missing here is a metric that would be graphed as a bare number.
    UNITS = COLLECTORS.each_value.reduce({}) { |units, collector| units.merge(collector::UNITS) }.freeze

    def initialize(namespace:, app:, environment:, role:, collect:, logger:, out: $stdout)
      @namespace = namespace
      @app = app
      @environment = environment
      @role = role
      @logger = logger
      @out = out
      @collectors = Array(collect).map do |name|
        COLLECTORS.fetch(name) { raise ArgumentError, "Unknown metrics to collect: #{name.inspect}" }
      end
    end

    # The interval is an argument so that the sampling itself can be tested. Production takes the
    # default, because an alarm's period is built around a sample a minute.
    def start(interval: INTERVAL)
      @stopping = false
      @last_failure = nil

      @thread = Thread.new do
        Thread.current.name = "runtime-metrics"
        # Nothing here is worth a backtrace on stderr, and nothing here is worth stopping the
        # process for: every failure is handled below.
        Thread.current.report_on_exception = false

        loop do
          sleep interval
          break if @stopping

          publish
        end
      end

      at_exit { stop }
      self
    end

    def stop
      return unless running?

      @stopping = true
      @thread.wakeup
      @thread.join(5)
    end

    # Whether this process is sampling, which is the question a console in a container asks.
    def running?
      @thread&.alive? || false
    end

    def document(now: Time.now.utc)
      measured = values(now)
      declared = measured.keys.map { |name| { "Name" => name, "Unit" => UNITS.fetch(name) } }

      # Generated rather than serialised with `to_json`: in a Rails process that is Active Support's
      # encoder, which escapes for HTML and asks every value for its own `as_json`.
      JSON.generate({
        "_aws" => {
          "Timestamp" => (now.to_f * 1000).round,
          "CloudWatchMetrics" => [ {
            "Namespace" => @namespace,
            "Dimensions" => [ %w[App Environment Role] ],
            "Metrics" => declared
          } ]
        },
        "App" => @app,
        "Environment" => @environment,
        "Role" => @role
      }.merge(measured))
    end

    private
      def publish
        @out.puts(document)
        @out.flush
        @last_failure = nil
      rescue StandardError => e
        report(e)
      end

      # A minute is often enough that a lasting failure would drown the log it shares with the
      # application's own, so the same one is said once and again only when it changes.
      def report(error)
        failure = "#{error.class}: #{error.message}"
        return if failure == @last_failure

        @last_failure = failure
        @logger.warn("Runtime metrics are not being reported: #{failure}")
      end

      # A collector that cannot see its runtime in this process contributes nothing, and a number it
      # has nothing to measure yet is left out rather than reported as zero.
      def values(now)
        @collectors.map(&:new)
                   .select(&:available?)
                   .reduce({}) { |all, collector| all.merge(collector.values(now)) }
                   .compact
      end
  end
end
