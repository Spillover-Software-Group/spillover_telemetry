# frozen_string_literal: true

require "test_helper"

class SettingsTest < ActiveSupport::TestCase
  METRICS = {
    "CLOUDWATCH_METRICS_NAMESPACE" => "Spillover/Runtime",
    "CLOUDWATCH_METRICS_APP" => "my-reviews-api",
    "CLOUDWATCH_METRICS_ROLE" => "web"
  }.freeze

  test "reports metrics where a namespace names them" do
    assert_predicate settings(METRICS), :metrics?
  end

  test "reports no metrics where no namespace is set" do
    assert_not_predicate settings, :metrics?
  end

  test "names the variable a deploy set a namespace without" do
    error = assert_raises(KeyError) { settings("CLOUDWATCH_METRICS_NAMESPACE" => "Spillover/Runtime") }

    assert_includes error.message, "CLOUDWATCH_METRICS_APP"
  end

  test "takes the collectors a deploy named" do
    assert_equal [ :puma, :solid_queue ],
                 settings(METRICS.merge("CLOUDWATCH_METRICS_COLLECT" => "puma, solid_queue")).collect
  end

  test "names no collectors where the deploy named none" do
    assert_nil settings(METRICS).collect
  end

  test "reports errors where a DSN is set" do
    assert_predicate settings("SENTRY_DSN" => "https://public@sentry.invalid/1"), :errors?
  end

  test "reports no errors where no DSN is set" do
    assert_not_predicate settings, :errors?
  end

  test "reports traces where an OTLP endpoint is set" do
    assert_predicate settings("OTEL_EXPORTER_OTLP_ENDPOINT" => "http://localhost:4318"), :traces?
  end

  test "reports no traces where no OTLP endpoint is set" do
    assert_not_predicate settings, :traces?
  end

  test "takes the release from the version Kamal deployed" do
    assert_equal "5f2d1c9", settings("KAMAL_VERSION" => "5f2d1c9").release
  end

  test "reports as the destination Kamal deployed to" do
    assert_equal "staging", settings("KAMAL_DESTINATION" => "staging").environment("production")
  end

  test "reports as the Rails environment where there is no destination" do
    assert_equal "production", settings({}).environment("production")
  end

  test "lets a signal name its own environment over the destination" do
    assert_equal "canary", settings("KAMAL_DESTINATION" => "staging").environment("canary", "production")
  end

  # A `deploy.yml` that names a variable it has nothing to put in still passes an empty one.
  test "reads a variable that is set to nothing as one that is not set" do
    assert_not_predicate settings("SENTRY_DSN" => ""), :errors?
  end

  private
    def settings(environment = {})
      SpilloverTelemetry::Settings.from_env(environment)
    end
end
