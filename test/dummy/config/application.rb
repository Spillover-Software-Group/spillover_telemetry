# frozen_string_literal: true

require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "solid_queue"

require "spillover_telemetry"

# The smallest Rails application the gem can be booted inside. The suite boots it in a process of
# its own, with the environment a container would pass, because every switch the gem reads is read
# once at boot and a process can only be one thing.
module Dummy
  class Application < ::Rails::Application
    config.load_defaults 7.1
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.secret_key_base = "spillover_telemetry_dummy"
    config.logger = ::Logger.new(File::NULL)

    # An application writes both of these with literal values. Here they come from the environment,
    # because the process that sets them is not the process that reads them.
    if ENV["DUMMY_SENTRY_BREADCRUMBS"]
      config.spillover_telemetry.sentry = ->(sentry) { sentry.max_breadcrumbs = Integer(ENV["DUMMY_SENTRY_BREADCRUMBS"]) }
    end

    if ENV["DUMMY_UNTRACED_ENDPOINT"]
      config.spillover_telemetry.instrumentation = {
        "OpenTelemetry::Instrumentation::Rack" => { untraced_endpoints: [ ENV["DUMMY_UNTRACED_ENDPOINT"] ] }
      }
    end

    if defined?(::SemanticLogger)
      # Semantic Logger's own default is a log file under the application root. A probe reports what
      # it made of its environment and writes no line anybody reads.
      config.rails_semantic_logger.add_file_appender = false

      # An application that names the environment its lines are stamped with names it here, where
      # the gem has already set one and an application's own word is the last.
      config.semantic_logger.environment = ENV["DUMMY_LOG_ENVIRONMENT"] if ENV["DUMMY_LOG_ENVIRONMENT"]
    end
  end
end
