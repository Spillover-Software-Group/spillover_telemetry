# frozen_string_literal: true

require "active_support/core_ext/object/blank"

module SpilloverTelemetry
  # Every variable the three signals read, taken from the environment once. It is read here rather
  # than where it is used because a lookup in a running process is one nobody can test, and because
  # a RuboCop that forbids an environment lookup in an initializer is happy to see it in a gem.
  #
  # A variable that is absent or empty reads as nil, and nil is what turns its signal off.
  Settings = Data.define(:metrics_namespace, :metrics_app, :metrics_role, :collect,
                         :sentry_dsn, :sentry_environment, :release, :otlp_endpoint, :destination) do
    def self.from_env(env = ENV)
      namespace = env["CLOUDWATCH_METRICS_NAMESPACE"].presence

      new(
        metrics_namespace: namespace,
        # A namespace on its own is not a configuration: a document with no application and no role
        # is a series nobody can find, so a deploy that sets one of the three says so at boot.
        metrics_app: namespace && env.fetch("CLOUDWATCH_METRICS_APP"),
        metrics_role: namespace && env.fetch("CLOUDWATCH_METRICS_ROLE"),
        collect: collect_from(env["CLOUDWATCH_METRICS_COLLECT"]),
        sentry_dsn: env["SENTRY_DSN"].presence,
        sentry_environment: env["SENTRY_ENVIRONMENT"].presence,
        release: env["KAMAL_VERSION"].presence,
        otlp_endpoint: env["OTEL_EXPORTER_OTLP_ENDPOINT"].presence,
        # Every destination of an application runs as the production Rails environment, so Rails.env
        # cannot tell staging from production; the destination Kamal deployed to can, and Kamal sets
        # it in every container.
        destination: env["KAMAL_DESTINATION"].presence
      )
    end

    # The collectors a process reports from, where what the process is does not say it. A web role
    # that runs its queue inside Puma is the case that needs it: one process, both sets of numbers.
    def self.collect_from(value)
      value.presence&.split(",")&.map { |name| name.strip.to_sym }
    end

    # What a signal reports as its environment: what the deploy said for that signal, else the
    # destination, else the Rails environment a process outside a container runs as.
    def environment(named = nil, rails_env)
      named || destination || rails_env
    end

    def metrics? = !metrics_namespace.nil?
    def errors? = !sentry_dsn.nil?
    def traces? = !otlp_endpoint.nil?
  end
end
