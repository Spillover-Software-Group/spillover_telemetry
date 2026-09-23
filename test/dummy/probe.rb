# frozen_string_literal: true

# Boots the dummy application as one kind of process and writes, as JSON to the file DUMMY_REPORT
# names, what telemetry made of it. The suite runs this rather than booting in-process because every
# switch is read once at boot, and because "no OpenTelemetry constant at all" is only true of a
# process that never had one. The report is a file rather than stdout because boot writes there too.
#
# The kind of process is the first argument: a server, the Solid Queue supervisor, a Sidekiq one,
# or none of them.

require "json"
require "sentry/test_helper"

# The outbound HTTP client this process has loaded, where it has one. An application loads it from
# its Gemfile, which is a thing its whole process either did or did not do, so here it is a variable
# read before boot rather than a require inside a test.
require ENV["DUMMY_HTTP_CLIENT"] if ENV["DUMMY_HTTP_CLIENT"]

# How a container logs, where the container logs to stdout. An application requires it from its own
# application file, above the class it configures, because the railtie has to be loaded before the
# application is configured; a probe does the same.
require "rails_semantic_logger" if ENV["DUMMY_SEMANTIC_LOGGER"]

case ARGV.first
when "server"
  # What `rails server` loads, and the only thing that defines Rails::Server.
  require "rails/command"
  require "rails/commands/server/server_command"
when "jobs"
  # What `bin/jobs` is called, which is how the supervisor is told from a console or a runner.
  $PROGRAM_NAME = "/rails/bin/jobs"
when "sidekiq"
  # What the `sidekiq` command is called, and a Sidekiq that answers rather than one that would
  # need a Redis to. See test/support/sidekiq_runtime.rb.
  require "socket"
  require "support/sidekiq_runtime"
  SidekiqRuntime.claim(enqueued: 2, latencies: [ 30.0 ], retrying: 1,
                       processes: [ { "busy" => 1, "beat" => Time.now.utc.to_f,
                                      "hostname" => Socket.gethostname } ])
  $PROGRAM_NAME = "/usr/local/bundle/bin/sidekiq"
end

require_relative "config/environment"
require "support/queue_schema"

QueueSchema.load

def sentry_report
  return { initialized: false } unless Sentry.initialized?

  {
    initialized: true,
    environment: Sentry.configuration.environment,
    release: Sentry.configuration.release,
    max_breadcrumbs: Sentry.configuration.max_breadcrumbs,
    structured_logging: Sentry.configuration.rails.structured_logging.enabled?
  }
end

def traces_report
  return { defined: false } unless Object.const_defined?(:OpenTelemetry)

  registry = OpenTelemetry::Instrumentation.registry

  {
    defined: true,
    tracer_provider: OpenTelemetry.tracer_provider.class.name,
    service_name: OpenTelemetry.tracer_provider.resource.attribute_enumerator.to_h["service.name"],
    rack_installed: registry.lookup("OpenTelemetry::Instrumentation::Rack").installed?,
    untraced_endpoints: registry.lookup("OpenTelemetry::Instrumentation::Rack").config[:untraced_endpoints],
    active_record_installed: registry.lookup("OpenTelemetry::Instrumentation::ActiveRecord").installed?,
    faraday_installed: registry.lookup("OpenTelemetry::Instrumentation::Faraday").installed?,
    httpx_installed: registry.lookup("OpenTelemetry::Instrumentation::HTTPX").installed?
  }
end

# One real request to the server DUMMY_HTTP_REQUEST names, made with the client this process loaded,
# and the spans it left. The exporter is in memory and the probe's OTEL_TRACES_EXPORTER is none, so
# nothing goes out on the wire and there is nothing left to flush.
def client_spans
  url = ENV["DUMMY_HTTP_REQUEST"]
  return [] unless url

  exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
  OpenTelemetry.tracer_provider.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
  )

  case ENV.fetch("DUMMY_HTTP_CLIENT")
  when "faraday" then ::Faraday.get(url)
  when "httpx" then ::HTTPX.get(url)
  end

  exporter.finished_spans.map do |span|
    { name: span.name, kind: span.kind.to_s, attributes: span.attributes }
  end
end

def log_report
  return { defined: false } unless Object.const_defined?(:SemanticLogger)

  { defined: true, environment: SemanticLogger.environment }
end

# What the application answered each request DUMMY_REQUESTS names, and what the error it reported
# said. Sentry keeps the configuration the boot gave it and swaps only its transport for the SDK's
# own test double, so nothing leaves the process.
def requests_report
  requests = JSON.parse(ENV.fetch("DUMMY_REQUESTS"))
  return [] if requests.empty?

  Sentry::TestHelper.setup_sentry_test if Sentry.initialized?

  requests.map do |request|
    env = Rack::MockRequest.env_for(request.fetch("path"), method: request["method"], input: request["input"])
    status, = Rails.application.call(env.merge(request.fetch("env", {})))
    event = Sentry::TestHelper.sentry_events.pop if Sentry.initialized?

    { status: status, user: event&.user, request: event&.request&.to_h }
  end
end

def metrics_report
  metrics = SpilloverTelemetry.metrics

  return { running: false } unless metrics

  { running: metrics.running?, document: JSON.parse(metrics.document) }
end

File.write(ENV.fetch("DUMMY_REPORT"),
           JSON.generate(sentry: sentry_report, traces: traces_report, metrics: metrics_report,
                         log: log_report, client_spans: client_spans, requests: requests_report))

# The report is written, and what a probe boots is more than it needs to shut down: Sentry's own
# `at_exit` flushes to a DSN that points at nothing here and raises when it cannot. A boot that
# failed leaves no report at all, which is what the suite reads.
exit!(0)
