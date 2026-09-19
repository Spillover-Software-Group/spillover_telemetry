# frozen_string_literal: true

require "sentry-rails"

module SpilloverTelemetry
  # Errors go to Sentry. Without a DSN `Sentry.init` never runs, the SDK stays uninitialized and the
  # middleware sentry-rails inserts passes every request through untouched, which is why the SDK can
  # be loaded in every process and still cost a container with no DSN nothing.
  module Errors
    def self.install(dsn:, environment:, release:, customize: nil)
      # Outbound calls made with httpx become breadcrumbs on whatever error follows them. The
      # adapter is Sentry's own, required here rather than at load because an application that does
      # not use httpx has nothing to adapt.
      require "httpx/adapters/sentry" if Object.const_defined?(:HTTPX)

      ::Sentry.init do |config|
        config.dsn = dsn
        # Both destinations of an application run as the production Rails environment; the
        # destination is what tells them apart. Kamal names the running version after the commit.
        config.environment = environment
        config.release = release
        # Everything an application wants beyond those three, so that it never writes a second
        # `Sentry.init` and loses them.
        customize&.call(config)
      end
    end
  end
end
