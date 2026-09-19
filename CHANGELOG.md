# Changelog

Versions are semver tags. An application pins one.

## v0.1.3

- Metrics and errors report as the destination Kamal deployed to (`KAMAL_DESTINATION`), not as
  `Rails.env`. Every destination of an application runs as the production Rails environment, so a
  staging container's metrics landed on the production series, where the production alarms read
  them. `SENTRY_ENVIRONMENT` still overrides errors; a process outside a container reports as
  `Rails.env`, as before.

## v0.1.2

- Traces cover an application's outbound HTTP as well as its inbound: the gem carries the Faraday
  and HTTPX instrumentations beside the Rails bundle, and a call an application makes to another
  service is a client span on the same trace as the request that made it. Neither instrumentation
  loads its client and neither installs where the process has none, so an application adds nothing
  to its own Gemfile and a process with no client is unchanged.

  The HTTPX instrumentation patches httpx 1.6 and up. A process on an older httpx logs that it does
  not and goes on tracing everything else.

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
