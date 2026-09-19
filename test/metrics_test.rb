# frozen_string_literal: true

require "json"
require "logger"

require "test_helper"
require "support/puma_server"
require "support/transactional"

class MetricsTest < ActiveSupport::TestCase
  include PumaServer
  include Transactional

  # The sampler runs in a thread of its own, so a test waits on what it writes rather than on the
  # clock.
  class Stream
    def initialize
      @lines = Queue.new
    end

    def puts(line)
      @lines << line
    end

    def flush; end

    def take
      @lines.pop
    end
  end

  class UnwritableStream
    def initialize(failures)
      @failures = failures
    end

    def puts(_line)
      raise IOError, @failures.length > 1 ? @failures.shift : @failures.first
    end

    def flush; end
  end

  class LogLines < Stream
    alias_method :write, :puts
    alias_method :close, :flush
  end

  test "declares every value it reports, with that value's unit" do
    start_puma_server
    document = emit
    reported = document.keys - %w[_aws App Environment Role]

    assert_equal reported.map { |name| { "Name" => name, "Unit" => SpilloverTelemetry::Metrics::UNITS.fetch(name) } },
                 document.dig("_aws", "CloudWatchMetrics", 0, "Metrics")
  end

  test "dimensions the document by application, environment and role" do
    assert_equal [ %w[App Environment Role] ], emit.dig("_aws", "CloudWatchMetrics", 0, "Dimensions")
  end

  test "names the application, environment and role it was emitted for" do
    assert_equal [ "my-reviews-api", "production", "web" ], emit.values_at("App", "Environment", "Role")
  end

  test "names the namespace it was emitted into" do
    assert_equal "Spillover/Runtime", emit.dig("_aws", "CloudWatchMetrics", 0, "Namespace")
  end

  test "timestamps the document in milliseconds" do
    assert_equal 1_767_323_045_000, emit(now: Time.utc(2026, 1, 2, 3, 4, 5)).dig("_aws", "Timestamp")
  end

  test "reports both runtimes where the process asked for both" do
    start_puma_server

    assert_equal %w[PumaBacklog PumaPoolCapacity PumaRunningThreads QueueDepth FailedJobs],
                 emit.keys - %w[_aws App Environment Role]
  end

  test "refuses a collector it has no numbers for" do
    assert_raises(ArgumentError) { build(collect: [ :everything ]) }
  end

  test "writes a document to the stream it was given" do
    stream = Stream.new
    metrics = build(out: stream).start(interval: 0.01)

    assert_equal "Spillover/Runtime", JSON.parse(stream.take).dig("_aws", "CloudWatchMetrics", 0, "Namespace")
  ensure
    metrics.stop
  end

  test "goes on sampling where a document cannot be written" do
    lines = LogLines.new
    metrics = build(out: UnwritableStream.new([ "the pipe is gone" ]), logger: Logger.new(lines)).start(interval: 0.01)
    lines.take

    assert_predicate metrics, :running?
  ensure
    metrics.stop
  end

  test "reports the same failure once, and reports a new one when it changes" do
    lines = LogLines.new
    metrics = build(out: UnwritableStream.new([ "the pipe is gone", "the pipe is gone", "the disk is full" ]),
                    logger: Logger.new(lines)).start(interval: 0.01)

    assert_includes lines.take, "the pipe is gone"
    assert_includes lines.take, "the disk is full"
  ensure
    metrics.stop
  end

  test "stops sampling when it is stopped" do
    metrics = build.start(interval: 0.01)
    metrics.stop

    assert_not_predicate metrics, :running?
  end

  private
    def build(collect: [ :puma, :solid_queue ], out: Stream.new, logger: Logger.new(File::NULL))
      SpilloverTelemetry::Metrics.new(namespace: "Spillover/Runtime", app: "my-reviews-api",
                                      environment: "production", role: "web", collect: collect,
                                      logger: logger, out: out)
    end

    def emit(collect: [ :puma, :solid_queue ], now: Time.now.utc)
      JSON.parse(build(collect: collect).document(now: now))
    end
end
