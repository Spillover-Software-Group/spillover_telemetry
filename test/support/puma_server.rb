# frozen_string_literal: true

require "puma"

# A real Puma server on an ephemeral port, which is the only thing that makes Puma publish the
# numbers the collector reads. Puma answers through whichever object claimed the reader when it
# started, so the test claims it the way Puma's own launcher does, and gives it back afterwards.
module PumaServer
  def start_puma_server
    @puma_server = ::Puma::Server.new(->(_env) { [ 200, {}, [ "" ] ] })
    @puma_server.add_tcp_listener("127.0.0.1", 0)
    @puma_server.run
    ::Puma.stats_object = @puma_server
  end

  def after_teardown
    super
    ::Puma.stats_object = nil
    @puma_server&.stop(true)
  end
end
