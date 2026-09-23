# frozen_string_literal: true

require_relative "spillover_telemetry/version"
require_relative "spillover_telemetry/settings"
require_relative "spillover_telemetry/metrics"
require_relative "spillover_telemetry/errors"
require_relative "spillover_telemetry/client_address"
require_relative "spillover_telemetry/traces"

# How a Spillover Rails application reports on itself: runtime metrics on stdout, errors to Sentry,
# and traces to an OTLP endpoint. Each is off until the deploy sets its one variable, and the
# Railtie is the whole of the wiring an application has to do.
module SpilloverTelemetry
  class << self
    # What this process reports, or nil where it reports nothing. A console in a container answers
    # with it.
    attr_accessor :metrics

    # Read at the first thing that asks and kept, because a variable read while the process runs is
    # a variable nobody can test.
    def settings
      @settings ||= Settings.from_env
    end

    # The user the current request is for, named where the application authenticates it. Every
    # error the request raises names them by this id and email, beside the address the gem names
    # for every request.
    def identify_user(id:, email:)
      Errors.identify(id: id, email: email)
    end
  end
end

require_relative "spillover_telemetry/railtie"
