# frozen_string_literal: true

module SpilloverTelemetry
  # Traces go to an OTLP endpoint. Nothing OpenTelemetry is loaded until `install` runs, so a
  # container with no endpoint has no OpenTelemetry constant defined at all.
  module Traces
    # The Rails instrumentation is a bundle, one instrumentation per framework, and `use_all` is how
    # a bundle is installed: naming the Rails one alone installs an empty umbrella that traces
    # nothing. Two of the bundle are turned down here. Active Record traces transactions and nothing
    # else, and a job process polling its queue is a transaction a second, each of which would be a
    # trace of its own. The health check is the load balancer asking every fifteen seconds, and
    # answers nothing a trace could add to.
    INSTRUMENTATION = {
      "OpenTelemetry::Instrumentation::ActiveRecord" => { enabled: false },
      "OpenTelemetry::Instrumentation::Rack" => { untraced_endpoints: [ "/health" ] }
    }.freeze

    # The service name is deliberately not set here: the SDK reads `OTEL_SERVICE_NAME` itself, and a
    # container that forgets it reports as `unknown_service`, which is visible and wrong rather than
    # quietly counted as another application.
    #
    # An application's own options are merged over these by instrumentation name, so turning one on
    # does not mean restating the rest. A name it names it owns outright.
    def self.install(instrumentation = {})
      require "opentelemetry/sdk"
      require "opentelemetry/exporter/otlp"
      require "opentelemetry/instrumentation/rails"

      ::OpenTelemetry::SDK.configure do |config|
        config.use_all(INSTRUMENTATION.merge(instrumentation))
      end
    end
  end
end
