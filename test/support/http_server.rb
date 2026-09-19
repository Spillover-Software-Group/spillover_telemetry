# frozen_string_literal: true

require "puma"

# A real server on an ephemeral port for the probes that call out of the process. A client span is
# only written by a client that made a request and read a response, so there is something for it to
# have made a request to.
module HTTPServer
  def start_http_server
    @http_server = ::Puma::Server.new(->(_env) { [ 200, { "content-type" => "text/plain" }, [ "ok" ] ] })
    @http_server_port = @http_server.add_tcp_listener("127.0.0.1", 0).addr[1]
    @http_server.run
  end

  def http_server_url
    "http://127.0.0.1:#{@http_server_port}/"
  end

  def after_teardown
    super
    @http_server&.stop(true)
  end
end
