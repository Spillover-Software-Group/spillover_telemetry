# frozen_string_literal: true

require_relative "lib/spillover_telemetry/version"

Gem::Specification.new do |spec|
  spec.name = "spillover_telemetry"
  spec.version = SpilloverTelemetry::VERSION
  spec.authors = [ "Spillover Software Group" ]
  spec.email = [ "devteam@spillover.com" ]

  spec.summary = "How a Spillover Rails application reports on itself"
  spec.description = "Runtime metrics on stdout as CloudWatch Embedded Metric Format, errors to " \
                     "Sentry and traces to an OTLP endpoint, each behind the one environment " \
                     "variable that configures it."
  spec.homepage = "https://github.com/Spillover-Software-Group/spillover_telemetry"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE"]
  spec.require_paths = [ "lib" ]

  # The oldest Rails any application taking this gem runs. Nothing here calls a Rails API newer than
  # that: the Railtie, the two extension points and the queue collector's `with_connection` are all
  # 6.1's. The OpenTelemetry instrumentations for Rails patch 7.1 and up and say so themselves, so a
  # 6.1 application reports metrics and errors and is told what it is not tracing.
  spec.add_dependency "railties", ">= 6.1"
  spec.add_dependency "sentry-rails", ">= 7.0"

  # Carried so that an application's Gemfile names this gem and nothing else, and loaded only by
  # SpilloverTelemetry::Traces, which runs only where an OTLP endpoint is set: Bundler requires what
  # a Gemfile names, never a gem's own dependencies. The two HTTP client instrumentations carry no
  # dependency on their client, and each installs only where the process has loaded one.
  spec.add_dependency "opentelemetry-exporter-otlp", ">= 0.36"
  spec.add_dependency "opentelemetry-instrumentation-faraday", ">= 0.33"
  spec.add_dependency "opentelemetry-instrumentation-httpx", ">= 0.8"
  spec.add_dependency "opentelemetry-instrumentation-rails", ">= 0.42"
  spec.add_dependency "opentelemetry-sdk", ">= 1.13"
end
