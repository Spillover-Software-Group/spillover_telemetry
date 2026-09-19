# Changelog

Versions are semver tags. An application pins one.

## v0.1.1

- The `puma` collector reports a clustered Puma. The sampling process in a cluster is the master,
  whose stats carry one status per worker rather than a pool of its own, so the collector now sums
  the workers' backlog, capacity and running threads; a worker that has not booted counts for
  nothing. Single mode is unchanged. Before this, a `web` role with `WEB_CONCURRENCY` above 1
  published documents with no Puma metrics at all, and its backlog alarm had no data.

## v0.1.0

The three files every Spillover Rails application carried a copy of, as one gem: runtime metrics on
stdout, errors to Sentry, and traces to an OTLP endpoint, each behind the variable the deploy already
sets.

- `SpilloverTelemetry::Metrics`, with a collector per runtime (`puma`, `solid_queue`) chosen from
  what the process is, or named by `CLOUDWATCH_METRICS_COLLECT`.
- `SpilloverTelemetry::Errors`, and `config.spillover_telemetry.sentry` for what an application wants
  beyond the DSN, the environment and the release.

  One deliberate change from the initializers this replaces: **sentry-rails' structured logging is
  off**. Its default forwards every Active Record and Action Controller log line to Sentry, which
  both applications have been doing since sentry-rails 7.0. An application that wants it turns it
  back on in its own `sentry` block.
- `SpilloverTelemetry::Traces`, and `config.spillover_telemetry.instrumentation` for what an
  application wants beyond the Rails bundle without Active Record and with `/health` untraced. The
  service name comes from `OTEL_SERVICE_NAME` rather than from code.
