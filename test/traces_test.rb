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

  test "traces a GraphQL operation an application executes, by its name" do
    span = graphql_request.fetch(:spans).find { |candidate| candidate[:name] == "graphql.execute_query" }

    assert_equal %w[Greeting query], span&.dig(:attributes)&.values_at(:"graphql.operation.name", :"graphql.operation.type")
  end

  test "traces the operation inside the trace of the request that carried it" do
    spans = graphql_request.fetch(:spans)

    assert_equal 1, spans.map { |span| span[:trace_id] }.uniq.length, spans.inspect
  end

  test "instruments GraphQL nowhere the process has not loaded it" do
    assert_equal [ false, true ],
                 [ boot(**IN_MEMORY), boot(**IN_MEMORY, DUMMY_GRAPHQL: "1") ].map { |telemetry| telemetry.dig(:traces, :graphql_installed) }
  end

  test "defines no OpenTelemetry constant where GraphQL is loaded and no endpoint is set" do
    assert_not boot(DUMMY_GRAPHQL: "1").dig(:traces, :defined)
  end

  test "names the trace a request is in the way X-Ray names it" do
    request = answer_request
    hex = server_span(request).fetch(:trace_id)

    assert_equal "1-#{hex[0, 8]}-#{hex[8, 24]}", request[:trace_id]
  end

  test "names no trace where nothing is traced" do
    request = boot(requests: [ { path: "/answer" } ]).fetch(:requests).first

    assert_equal [ 200, nil ], request.values_at(:status, :trace_id)
  end

  test "annotates the request's span with what the application says of it" do
    attributes = server_span(answer_request(path: "/answer?id=42")).fetch(:attributes)

    assert_equal [ "42", "answer" ], attributes.values_at(:account_id, :operation)
  end

  test "lists every annotation for X-Ray to index, not only the last call's" do
    attributes = server_span(answer_request(path: "/answer?id=42")).fetch(:attributes)

    assert_equal %w[account_id operation], attributes[:"aws.xray.annotations"]
  end

  test "annotates nothing where nothing is traced" do
    assert_equal 200, boot(requests: [ { path: "/answer?id=42" } ]).fetch(:requests).first[:status]
  end

  private
    def graphql_request
      request = { path: "/graphql", method: "POST", env: { "CONTENT_TYPE" => "application/json" },
                  input: JSON.generate(query: "query Greeting { greeting }", operationName: "Greeting") }

      boot(**IN_MEMORY, DUMMY_GRAPHQL: "1", requests: [ request ]).fetch(:requests).first
    end

    def answer_request(path: "/answer")
      boot(**IN_MEMORY, requests: [ { path: path } ]).fetch(:requests).first
    end

    def server_span(request)
      request.fetch(:spans).find { |span| span[:kind] == "server" } || flunk("no server span in #{request.inspect}")
    end

    def call_with(client)
      boot(**IN_MEMORY, DUMMY_HTTP_CLIENT: client, DUMMY_HTTP_REQUEST: http_server_url)
    end

    def client_span(telemetry)
      spans = telemetry.fetch(:client_spans)

      assert_equal 1, spans.length, "expected one client span, got #{spans.inspect}"
      spans.first
    end
end
