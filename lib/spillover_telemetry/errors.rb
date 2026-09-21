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
        # sentry-rails forwards every Active Record and Action Controller log line to Sentry unless
        # it is told not to. Sentry is where errors go, the logs already go to CloudWatch, and a copy
        # of the SQL and the controller timings is traffic and cost nobody asked for. Set before the
        # block, so an application that wants it can have it.
        config.rails.structured_logging.enabled = false
        # `bin/rails runner` reports whatever ended it, and an ordinary non-zero exit ends it with
        # a SystemExit: a one-off command that a person ran and watched fail arrives as an
        # unresolved issue nobody can act on, since the exit status already said so where it was
        # typed. An application raising SystemExit in a request or a job would be reporting the
        # same thing, so the exclusion is the gem's rather than each application's.
        config.excluded_exceptions += [ "SystemExit" ]
        # Everything an application wants beyond those, so that it never writes a second
        # `Sentry.init` and loses them.
        customize&.call(config)
      end
    end
  end
end
