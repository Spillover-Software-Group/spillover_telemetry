# frozen_string_literal: true

require "sentry-rails"

module SpilloverTelemetry
  # Errors go to Sentry. Without a DSN `Sentry.init` never runs, the SDK stays uninitialized and the
  # middleware sentry-rails inserts passes every request through untouched, which is why the SDK can
  # be loaded in every process and still cost a container with no DSN nothing.
  module Errors
    def self.install(dsn:, environment:, release:, customize: nil)
      ::Sentry.init do |config|
        config.dsn = dsn
        # Both destinations of an application run as the production Rails environment; the
        # destination is what tells them apart. Kamal names the running version after the commit.
        config.environment = environment
        config.release = release
        # An error says of the request it happened in only the method and the URL. With
        # `send_default_pii` off the SDK leaves out the cookies, the body, the query string and the
        # address, but not the headers, nor the Rack environment it filters by the same setting.
        config.data_collection.http_headers.request = false
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

    # Adds to the user every error in the current scope names. sentry-rails opens a scope for each
    # request and each job and closes it when they end, so a user goes with the request that named
    # them. Where errors are not reported there is no scope, and this does nothing.
    def self.identify(**user)
      scope = ::Sentry.get_current_scope
      scope&.set_user(scope.user.merge(user))
    end
  end
end
