# frozen_string_literal: true

require "test_helper"
require "support/probe"

# What a booted application makes of its environment: one process per test, because every switch is
# read once at boot.
class RailtieTest < ActiveSupport::TestCase
  include Probe

  DSN = "http://public@127.0.0.1:1/1"
  ENDPOINT = "http://127.0.0.1:4318"
  METRICS = {
    CLOUDWATCH_METRICS_NAMESPACE: "Spillover/Runtime",
    CLOUDWATCH_METRICS_APP: "my-reviews-api",
    CLOUDWATCH_METRICS_ROLE: "web"
  }.freeze
  # A client at 198.51.100.23 reaching the application through a load balancer and a proxy on the
  # private network. Each adds the address it was called from to X-Forwarded-For, and the
  # application is called by the last.
  BEHIND_PROXIES = { "REMOTE_ADDR" => "172.18.0.2", "HTTP_X_FORWARDED_FOR" => "198.51.100.23, 10.0.1.17" }.freeze
  SIGNED_IN = "id=7&email=owner%40example.com"
  # A form posted with everything a browser sends beside it: a query, a cookie and the headers.
  FORM = { path: "/fail?token=secret", method: "POST", input: "reply=Thanks",
           env: { "CONTENT_TYPE" => "application/x-www-form-urlencoded", "HTTP_COOKIE" => "session=secret",
                  "HTTP_USER_AGENT" => "Mozilla/5.0", "HTTP_REFERER" => "https://example.org/?token=secret" } }.freeze

  test "reports nothing at all where the deploy set no variable" do
    telemetry = boot

    assert_equal [ false, false, false ],
                 [ telemetry[:sentry][:initialized], telemetry[:traces][:defined], telemetry[:metrics][:running] ]
  end

  test "initializes Sentry where a DSN is set" do
    assert boot(SENTRY_DSN: DSN).dig(:sentry, :initialized)
  end

  test "reports errors as the Rails environment where the deploy names none" do
    assert_equal "test", boot(SENTRY_DSN: DSN).dig(:sentry, :environment)
  end

  test "reports errors as the environment the deploy names" do
    assert_equal "staging", boot(SENTRY_DSN: DSN, SENTRY_ENVIRONMENT: "staging").dig(:sentry, :environment)
  end

  test "reports errors as the destination Kamal deployed to where the deploy names none" do
    assert_equal "staging", boot(SENTRY_DSN: DSN, KAMAL_DESTINATION: "staging").dig(:sentry, :environment)
  end

  test "reports errors against the version Kamal deployed" do
    assert_equal "5f2d1c9", boot(SENTRY_DSN: DSN, KAMAL_VERSION: "5f2d1c9").dig(:sentry, :release)
  end

  # The logs go to CloudWatch. A second copy of the SQL and the controller timings at Sentry is
  # traffic and cost nobody asked for.
  test "sends no logs to Sentry" do
    assert_not boot(SENTRY_DSN: DSN).dig(:sentry, :structured_logging)
  end

  test "sends the user agent of a failed request" do
    assert_equal "Mozilla/5.0", boot(SENTRY_DSN: DSN, requests: [ FORM ]).dig(:requests, 0, :request, :headers, :"User-Agent")
  end

  # The SDK keeps the name of every header it does not send, with the value masked.
  test "sends nothing else of a failed request but its method and its URL" do
    request = boot(SENTRY_DSN: DSN, requests: [ FORM ]).dig(:requests, 0, :request)

    assert_equal({ method: "POST", url: "http://example.org/fail", cookies: {},
                   headers: { "Content-Length": "[Filtered]", "Content-Type": "[Filtered]", Cookie: "[Filtered]",
                              Referer: "[Filtered]", "X-Request-Id": "[Filtered]" },
                   env: { SERVER_NAME: "[Filtered]", SERVER_PORT: "[Filtered]" } },
                 request.merge(headers: request[:headers].except(:"User-Agent")))
  end

  test "reports an error in a request as the client it came from" do
    request = { path: "/fail", env: BEHIND_PROXIES }

    assert_equal({ ip_address: "198.51.100.23" }, boot(SENTRY_DSN: DSN, requests: [ request ]).dig(:requests, 0, :user))
  end

  test "reports an error as the user the application identified" do
    request = { path: "/fail?#{SIGNED_IN}", env: BEHIND_PROXIES }

    assert_equal({ id: "7", email: "owner@example.com", ip_address: "198.51.100.23" },
                 boot(SENTRY_DSN: DSN, requests: [ request ]).dig(:requests, 0, :user))
  end

  test "forgets the user when the request ends" do
    requests = [ { path: "/fail?#{SIGNED_IN}", env: BEHIND_PROXIES }, { path: "/fail", env: BEHIND_PROXIES } ]

    assert_equal({ ip_address: "198.51.100.23" }, boot(SENTRY_DSN: DSN, requests: requests).dig(:requests, 1, :user))
  end

  test "answers a request whose address Rails cannot tell" do
    request = { path: "/answer", env: BEHIND_PROXIES.merge("HTTP_CLIENT_IP" => "192.0.2.1") }

    assert_equal 200, boot(SENTRY_DSN: DSN, requests: [ request ]).dig(:requests, 0, :status)
  end

  test "answers a request that identifies its user where no DSN is set" do
    assert_equal 200, boot(requests: [ { path: "/answer?#{SIGNED_IN}" } ]).dig(:requests, 0, :status)
  end

  test "lets the application add to the Sentry configuration" do
    assert_equal 7, boot(SENTRY_DSN: DSN, DUMMY_SENTRY_BREADCRUMBS: "7").dig(:sentry, :max_breadcrumbs)
  end

  test "traces through the SDK where an OTLP endpoint is set" do
    assert_equal "OpenTelemetry::SDK::Trace::TracerProvider",
                 boot(OTEL_EXPORTER_OTLP_ENDPOINT: ENDPOINT).dig(:traces, :tracer_provider)
  end

  test "instruments the request where an OTLP endpoint is set" do
    assert boot(OTEL_EXPORTER_OTLP_ENDPOINT: ENDPOINT).dig(:traces, :rack_installed)
  end

  test "leaves Active Record untraced" do
    assert_not boot(OTEL_EXPORTER_OTLP_ENDPOINT: ENDPOINT).dig(:traces, :active_record_installed)
  end

  test "leaves the health check untraced" do
    assert_equal [ "/health" ], boot(OTEL_EXPORTER_OTLP_ENDPOINT: ENDPOINT).dig(:traces, :untraced_endpoints)
  end

  test "lets the application replace an instrumentation's options" do
    telemetry = boot(OTEL_EXPORTER_OTLP_ENDPOINT: ENDPOINT, DUMMY_UNTRACED_ENDPOINT: "/up")

    assert_equal [ "/up" ], telemetry.dig(:traces, :untraced_endpoints)
  end

  test "names the traced service as the SDK's own variable names it" do
    telemetry = boot(OTEL_EXPORTER_OTLP_ENDPOINT: ENDPOINT, OTEL_SERVICE_NAME: "my-reviews-api")

    assert_equal "my-reviews-api", telemetry.dig(:traces, :service_name)
  end

  # Visible and wrong beats quietly counted as another application.
  test "names the traced service unknown where the deploy names none" do
    assert_equal "unknown_service", boot(OTEL_EXPORTER_OTLP_ENDPOINT: ENDPOINT).dig(:traces, :service_name)
  end

  test "samples a server's runtime" do
    assert boot(as: "server", **METRICS).dig(:metrics, :running)
  end

  test "reports nothing of the queue from a server that does not run it" do
    assert_not_includes metric_names(boot(as: "server", **METRICS)), "QueueDepth"
  end

  test "samples the queue from the job supervisor" do
    assert_includes metric_names(boot(as: "jobs", **METRICS)), "QueueDepth"
  end

  test "reports nothing of Puma from the job supervisor" do
    assert_not_includes metric_names(boot(as: "jobs", **METRICS)), "PumaBacklog"
  end

  test "samples the queue from a Sidekiq process" do
    assert_includes metric_names(boot(as: "sidekiq", **METRICS)), "BusyWorkers"
  end

  test "reports nothing of Puma from a Sidekiq process" do
    assert_not_includes metric_names(boot(as: "sidekiq", **METRICS)), "PumaBacklog"
  end

  # Solid Queue is in that process too, because the dummy application mounts it, and the two queue
  # collectors report the same four names. Only the runtime the process is gets to fill them.
  test "fills the shared queue metrics from Sidekiq in a Sidekiq process" do
    document = boot(as: "sidekiq", **METRICS).dig(:metrics, :document)

    assert_equal [ 2, 30, 1 ], document.values_at(:QueueDepth, :OldestReadyJobAge, :FailedJobs)
  end

  test "samples nothing from a console, a runner or a rake task" do
    assert_not boot(**METRICS).dig(:metrics, :running)
  end

  test "samples the queue from a server where the deploy names both" do
    telemetry = boot(as: "server", **METRICS, CLOUDWATCH_METRICS_COLLECT: "puma,solid_queue")

    assert_includes metric_names(telemetry), "QueueDepth"
  end

  # The container passes the same environment to everything it starts, so the console in the web
  # container sees what the deploy named too.
  test "samples nothing from a console where the deploy names collectors" do
    assert_not boot(**METRICS, CLOUDWATCH_METRICS_COLLECT: "puma,solid_queue").dig(:metrics, :running)
  end

  test "dimensions a document by the application, environment and role the deploy named" do
    document = boot(as: "jobs", **METRICS).dig(:metrics, :document)

    assert_equal [ "my-reviews-api", "test", "web" ], document.values_at(:App, :Environment, :Role)
  end

  test "dimensions a document by the destination Kamal deployed to" do
    document = boot(as: "jobs", **METRICS, KAMAL_DESTINATION: "staging").dig(:metrics, :document)

    assert_equal "staging", document[:Environment]
  end

  test "stamps a log line with the destination Kamal deployed to" do
    telemetry = boot(DUMMY_SEMANTIC_LOGGER: "1", KAMAL_DESTINATION: "staging")

    assert_equal "staging", telemetry.dig(:log, :environment)
  end

  test "stamps a log line with the Rails environment where the deploy names no destination" do
    assert_equal "test", boot(DUMMY_SEMANTIC_LOGGER: "1").dig(:log, :environment)
  end

  test "leaves a log environment the application named alone" do
    telemetry = boot(DUMMY_SEMANTIC_LOGGER: "1", DUMMY_LOG_ENVIRONMENT: "canary", KAMAL_DESTINATION: "staging")

    assert_equal "canary", telemetry.dig(:log, :environment)
  end

  # Nothing of Semantic Logger is loaded by this gem, so an application that logs any other way is
  # an application where there is nothing to set.
  test "loads no logger of its own where the application has none" do
    assert_not boot(KAMAL_DESTINATION: "staging").dig(:log, :defined)
  end

  private
    def metric_names(telemetry)
      telemetry.dig(:metrics, :document, :_aws, :CloudWatchMetrics, 0, :Metrics).map { |metric| metric[:Name] }
    end
end
