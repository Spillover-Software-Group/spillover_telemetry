# frozen_string_literal: true

require "test_helper"
require "support/http_server"
require "support/probe"

# The outbound half of a trace: the calls an application makes to another service. One process per
# test, because whether a client is loaded at all is something a process either did at boot or did
# not, and the request is a real one to a real server.
class TracesTest < ActiveSupport::TestCase
  include HTTPServer
  include Probe

  ENDPOINT = "http://127.0.0.1:4318"
  # The spans are read out of the probe rather than off the wire, so nothing is exported and there
  # is nothing left for the process to flush.
  IN_MEMORY = { OTEL_EXPORTER_OTLP_ENDPOINT: ENDPOINT, OTEL_TRACES_EXPORTER: "none" }.freeze

  setup do
    start_http_server
  end

  test "traces a request an application makes with Faraday" do
    span = client_span(call_with("faraday"))

    assert_equal [ "GET", "client", 200 ],
                 [ span[:name], span[:kind], span.dig(:attributes, :"http.response.status_code") ]
  end

  test "names the server a Faraday request was made to" do
    span = client_span(call_with("faraday"))

    assert_equal "127.0.0.1", span.dig(:attributes, :"server.address")
  end

  test "traces a request an application makes with httpx" do
    span = client_span(call_with("httpx"))

    assert_equal [ "GET", "client", 200 ],
                 [ span[:name], span[:kind], span.dig(:attributes, :"http.response.status_code") ]
  end

  test "names the server an httpx request was made to" do
    span = client_span(call_with("httpx"))

    assert_equal "127.0.0.1", span.dig(:attributes, :"server.address")
  end

  test "instruments neither client where the process loaded neither" do
    telemetry = boot(**IN_MEMORY)

    assert_equal [ false, false ],
                 [ telemetry.dig(:traces, :faraday_installed), telemetry.dig(:traces, :httpx_installed) ]
  end

  # The client gems are in the bundle of every application that takes this gem, and carrying the
  # instrumentation for them must not change that a process with no endpoint loads no OpenTelemetry.
  test "defines no OpenTelemetry constant where an HTTP client is loaded and no endpoint is set" do
    assert_not boot(DUMMY_HTTP_CLIENT: "faraday").dig(:traces, :defined)
  end

  private
    def call_with(client)
      boot(**IN_MEMORY, DUMMY_HTTP_CLIENT: client, DUMMY_HTTP_REQUEST: http_server_url)
    end

    def client_span(telemetry)
      spans = telemetry.fetch(:client_spans)

      assert_equal 1, spans.length, "expected one client span, got #{spans.inspect}"
      spans.first
    end
end
