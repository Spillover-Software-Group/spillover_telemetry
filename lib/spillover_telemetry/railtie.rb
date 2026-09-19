# frozen_string_literal: true

require "rails/railtie"

module SpilloverTelemetry
  # The whole of the wiring: three signals, each started where the initializer it replaces used to
  # sit, and each doing nothing at all until the deploy sets its one variable.
  class Railtie < ::Rails::Railtie
    config.spillover_telemetry = ::ActiveSupport::OrderedOptions.new
    # Called with the Sentry configuration inside `Sentry.init`, after the settings below, so an
    # application adds to the configuration rather than repeating it in a second `Sentry.init`.
    config.spillover_telemetry.sentry = nil
    # Instrumentation options by name, merged over the gem's own.
    config.spillover_telemetry.instrumentation = {}

    # Late enough that the application's own initializers have set either extension point, and early
    # enough that Sentry's middleware and OpenTelemetry's are both in the stack Rails builds after
    # this.
    initializer "spillover_telemetry.install", after: :load_config_initializers do |app|
      settings = SpilloverTelemetry.settings
      options = app.config.spillover_telemetry

      if settings.errors?
        Errors.install(dsn: settings.sentry_dsn,
                       environment: settings.sentry_environment || ::Rails.env,
                       release: settings.release,
                       customize: options.sentry)
      end

      Traces.install(options.instrumentation) if settings.traces?
    end

    # The sampler starts once the application is up, because a collector reads the application's own
    # models and a process still booting has nothing worth reporting.
    config.after_initialize do
      settings = SpilloverTelemetry.settings
      collect = settings.collect || Railtie.collectors_for_this_process

      if settings.metrics? && collect.any?
        SpilloverTelemetry.metrics = Metrics.new(namespace: settings.metrics_namespace,
                                                 app: settings.metrics_app,
                                                 environment: ::Rails.env,
                                                 role: settings.metrics_role,
                                                 collect: collect,
                                                 logger: ::Rails.logger).start
      end
    end

    # An initializer runs in every process the image starts and the container passes them all the
    # same environment, so the process has to say what it is. `Rails::Server` is defined by the
    # command that starts a server and by no other, in every worker whether Puma is clustered or
    # not. `bin/jobs` starts the Solid Queue supervisor. A console, a runner and a rake task are
    # neither, and report nothing rather than printing a document a minute into someone's terminal.
    #
    # A process that is both, a server running its queue inside itself, says so with
    # CLOUDWATCH_METRICS_COLLECT, which is the one case this cannot tell from the outside.
    def self.collectors_for_this_process(program_name: $PROGRAM_NAME)
      if ::Rails.const_defined?(:Server)
        [ :puma ]
      elsif program_name.end_with?("bin/jobs")
        [ :solid_queue ]
      else
        []
      end
    end
  end
end
