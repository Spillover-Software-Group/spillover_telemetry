# frozen_string_literal: true

require "rails/railtie"

module SpilloverTelemetry
  # The whole of the wiring: three signals, each started where the initializer it replaces used to
  # sit, and each doing nothing at all until the deploy sets its one variable, and the one thing the
  # log needs to say the same environment they do.
  class Railtie < ::Rails::Railtie
    config.spillover_telemetry = ::ActiveSupport::OrderedOptions.new
    # Called with the Sentry configuration inside `Sentry.init`, after the settings below, so an
    # application adds to the configuration rather than repeating it in a second `Sentry.init`.
    config.spillover_telemetry.sentry = nil
    # Instrumentation options by name, merged over the gem's own.
    config.spillover_telemetry.instrumentation = {}

    # The environment a log line is stamped with, for an application that logs through Semantic
    # Logger. Its own default is RAILS_ENV, which every destination of an application runs as, so a
    # staging container's lines said production while the metric and the error beside them said
    # staging. `config.semantic_logger` is the `SemanticLogger` module itself rather than a set of
    # options applied later, so this is the value, read again at every line.
    #
    # It runs before the application is configured: the application class is not yet open, so
    # everything an application writes, its application file, its environment files and its
    # initializers, is later than this and an application that names its own environment keeps it.
    # Semantic Logger is loaded by then wherever it is loaded at all, because a container's
    # application file requires it above the class it configures.
    config.before_configuration do
      if defined?(::SemanticLogger)
        ::SemanticLogger.environment = SpilloverTelemetry.settings.environment(::Rails.env)
      end
    end

    # Late enough that the application's own initializers have set either extension point, and early
    # enough that Sentry's middleware and OpenTelemetry's are both in the stack Rails builds after
    # this.
    initializer "spillover_telemetry.install", after: :load_config_initializers do |app|
      settings = SpilloverTelemetry.settings
      options = app.config.spillover_telemetry

      if settings.errors?
        Errors.install(dsn: settings.sentry_dsn,
                       environment: settings.environment(settings.sentry_environment, ::Rails.env),
                       release: settings.release,
                       customize: options.sentry)
      end

      Traces.install(options.instrumentation) if settings.traces?
    end

    # The sampler starts once the application is up, because a collector reads the application's own
    # models and a process still booting has nothing worth reporting.
    config.after_initialize do
      settings = SpilloverTelemetry.settings
      collect = Railtie.collectors_for_this_process(settings.collect)

      if settings.metrics? && collect.any?
        SpilloverTelemetry.metrics = Metrics.new(namespace: settings.metrics_namespace,
                                                 app: settings.metrics_app,
                                                 environment: settings.environment(::Rails.env),
                                                 role: settings.metrics_role,
                                                 collect: collect,
                                                 logger: ::Rails.logger).start
      end
    end

    # What this process reports, given what the deploy named. The process decides whether it reports
    # at all and the variable decides what, never the other way round: a container passes the same
    # environment to everything it starts, so the console in the web container sees
    # CLOUDWATCH_METRICS_COLLECT too and must still say nothing.
    #
    # `Rails::Server` is defined by the command that starts a server and by no other, in every worker
    # whether Puma is clustered or not. `bin/jobs` starts the Solid Queue supervisor and the
    # `sidekiq` command starts a Sidekiq one, each named after what started it. A console, a runner
    # and a rake task are none of them, and report nothing rather than printing a document a minute
    # into someone's terminal. A server that runs its queue inside itself is what the variable exists
    # for, because that is the one thing a process cannot tell about itself.
    def self.collectors_for_this_process(named)
      if ::Rails.const_defined?(:Server)
        named || [ :puma ]
      elsif $PROGRAM_NAME.end_with?("bin/jobs")
        named || [ :solid_queue ]
      elsif $PROGRAM_NAME.end_with?("sidekiq")
        named || [ :sidekiq ]
      else
        []
      end
    end
  end
end
