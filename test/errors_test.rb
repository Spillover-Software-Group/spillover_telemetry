# frozen_string_literal: true

require "test_helper"

class ErrorsTest < ActiveSupport::TestCase
  DSN = "http://public@127.0.0.1:1/1"

  def teardown
    Sentry.close if Sentry.initialized?
  end

  test "initializes the SDK where it is given a DSN" do
    install

    assert_predicate Sentry, :initialized?
  end

  test "names the environment it was given" do
    install(environment: "staging")

    assert_equal "staging", Sentry.configuration.environment
  end

  test "names the release it was given" do
    install(release: "5f2d1c9")

    assert_equal "5f2d1c9", Sentry.configuration.release
  end

  # Events carry no cookies, no request bodies and no user address unless an application asks for
  # them, which is the SDK's own default and is left alone here.
  test "sends nothing personally identifying" do
    install

    assert_not Sentry.configuration.send_default_pii
  end

  # `bin/rails runner` reports a non-zero exit as a SystemExit, which is the shell's answer to the
  # person who typed the command rather than an error anyone can act on in Sentry.
  test "does not send a process exiting" do
    install

    assert_includes Sentry.configuration.excluded_exceptions, "SystemExit"
  end

  test "keeps the exceptions the SDK excludes of its own accord" do
    install

    assert_includes Sentry.configuration.excluded_exceptions, "ActiveRecord::RecordNotFound"
  end

  test "lets the caller add to the configuration" do
    install(customize: ->(sentry) { sentry.max_breadcrumbs = 7 })

    assert_equal 7, Sentry.configuration.max_breadcrumbs
  end

  test "keeps its own settings where the caller configures others" do
    install(release: "5f2d1c9", customize: ->(sentry) { sentry.max_breadcrumbs = 7 })

    assert_equal "5f2d1c9", Sentry.configuration.release
  end

  private
    def install(dsn: DSN, environment: "production", release: "5f2d1c9", customize: nil)
      SpilloverTelemetry::Errors.install(dsn: dsn, environment: environment, release: release,
                                         customize: customize)
    end
end
