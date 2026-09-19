# frozen_string_literal: true

# Boots the dummy application as one kind of process and writes, as JSON to the file DUMMY_REPORT
# names, what telemetry made of it. The suite runs this rather than booting in-process because every
# switch is read once at boot, and because "no OpenTelemetry constant at all" is only true of a
# process that never had one. The report is a file rather than stdout because boot writes there too.
#
# The kind of process is the first argument: a server, the Solid Queue supervisor, or neither.

require "json"

case ARGV.first
when "server"
  # What `rails server` loads, and the only thing that defines Rails::Server.
  require "rails/command"
  require "rails/commands/server/server_command"
when "jobs"
  # What `bin/jobs` is called, which is how the supervisor is told from a console or a runner.
  $PROGRAM_NAME = "/rails/bin/jobs"
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
    active_record_installed: registry.lookup("OpenTelemetry::Instrumentation::ActiveRecord").installed?
  }
end

def metrics_report
  metrics = SpilloverTelemetry.metrics

  return { running: false } unless metrics

  { running: metrics.running?, document: JSON.parse(metrics.document) }
end

File.write(ENV.fetch("DUMMY_REPORT"),
           JSON.generate(sentry: sentry_report, traces: traces_report, metrics: metrics_report))

# The report is written, and what a probe boots is more than it needs to shut down: Sentry's own
# `at_exit` flushes to a DSN that points at nothing here and raises when it cannot. A boot that
# failed leaves no report at all, which is what the suite reads.
exit!(0)
