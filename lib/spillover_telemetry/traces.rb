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
      # The outbound half of a trace: the calls an application makes to another service. Neither
      # instrumentation loads its client, and neither installs where the process has not: one asks
      # whether the constant is defined and, for HTTPX, whether the version is one it patches. A
      # process with an older client or none is told so in a line of its own and goes on tracing
      # everything else.
      require "opentelemetry/instrumentation/faraday"
      require "opentelemetry/instrumentation/httpx"
      # The operations inside a request to a GraphQL endpoint, which the request span alone cannot
      # tell apart: every one of them is a POST to the same path. Installs where the process loaded
      # graphql-ruby, as a span per query with the operation's name and type on it, and nothing per
      # field: a field span for every field of every query is more than a trace can be read through.
      require "opentelemetry/instrumentation/graphql"

      ::OpenTelemetry::SDK.configure do |config|
        config.use_all(INSTRUMENTATION.merge(instrumentation))
      end
    end

    # The id of the trace the current request is in, in the form X-Ray shows it, or nil where nothing
    # is traced. An application puts it on its log lines, so a line and its trace are found from each
    # other rather than by matching timestamps. X-Ray writes an OpenTelemetry trace id as `1-`, its
    # first eight hex digits, `-`, and the remaining twenty-four.
    def self.trace_id
      return unless defined?(::OpenTelemetry)

      context = ::OpenTelemetry::Trace.current_span.context
      return unless context.valid?

      hex = context.hex_trace_id
      "1-#{hex[0, 8]}-#{hex[8, 24]}"
    end

    # What an application says of the current request, worth finding its trace by: the operation it
    # ran, the account it ran as, whether it failed. Each becomes an attribute of the request's span,
    # and X-Ray indexes it as an annotation, so a filter of `annotation.account_id = 6063` in the
    # console finds every trace of that account. The exporter indexes an attribute only where the
    # span lists its key under `aws.xray.annotations`, which is how these are indexed without a word
    # of collector configuration; the list keeps what an earlier call put there. A nil says nothing,
    # and a process tracing nothing does nothing.
    def self.annotate(**facts)
      return unless defined?(::OpenTelemetry)

      span = ::OpenTelemetry::Trace.current_span
      return unless span.context.valid?

      facts = facts.compact.transform_keys(&:to_s)
      listed = span.attributes&.fetch("aws.xray.annotations", nil) if span.respond_to?(:attributes)
      span.add_attributes(facts.merge("aws.xray.annotations" => Array(listed) | facts.keys))
    end
  end
end
