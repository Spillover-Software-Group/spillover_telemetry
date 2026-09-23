# frozen_string_literal: true

module SpilloverTelemetry
  # Names the address a request came from on every error it raises. It is Rails' own
  # `request.remote_ip`, read past the proxies the application trusts, so an error names the client
  # the application itself sees, and `config.action_dispatch.trusted_proxies` moves both at once.
  class ClientAddress
    def initialize(app)
      @app = app
    end

    def call(env)
      name_address(env)
      @app.call(env)
    end

    private
      def name_address(env)
        Errors.identify(ip_address: ::ActionDispatch::Request.new(env).remote_ip)
      rescue ::ActionDispatch::RemoteIp::IpSpoofAttackError
        # Rails raises rather than choose between a Client-Ip and an X-Forwarded-For that disagree,
        # and a client can send either. That request names no address and goes on, to fail only
        # where the application asks for the address itself.
      end
  end
end
