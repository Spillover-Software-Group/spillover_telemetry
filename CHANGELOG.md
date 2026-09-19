# Changelog

Versions are semver tags. An application pins one.

## v0.1.0

The three files every Spillover Rails application carried a copy of, as one gem: runtime metrics on
stdout, errors to Sentry, and traces to an OTLP endpoint, each behind the variable the deploy already
sets.

- `SpilloverTelemetry::Metrics`, with a collector per runtime (`puma`, `solid_queue`) chosen from
  what the process is, or named by `CLOUDWATCH_METRICS_COLLECT`.
- `SpilloverTelemetry::Errors`, and `config.spillover_telemetry.sentry` for what an application wants
  beyond the DSN, the environment and the release.
- `SpilloverTelemetry::Traces`, and `config.spillover_telemetry.instrumentation` for what an
  application wants beyond the Rails bundle without Active Record and with `/health` untraced. The
  service name comes from `OTEL_SERVICE_NAME` rather than from code.
