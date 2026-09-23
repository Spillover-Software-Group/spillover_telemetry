# Changelog

Versions are semver tags. An application pins one.

## v0.3.0

- An error sends none of its request's headers. `send_default_pii` off kept the cookies, the body,
  the query string and the address out, but sent the headers, masked only where a name looked
  sensitive: the `User-Agent`, a `Referer` that can carry the query of another page, and the
  server's name and port beside them. An error says of its request only the method and the URL
  without its query.

## v0.2.2

- A process exiting is no longer an error. `bin/rails runner` reports whatever ended it, so a
  one-off command that exits non-zero raised a `SystemExit` issue in Sentry that nobody could act
  on: the exit status had already said so where the command was typed. `SystemExit` joins the
  exceptions the SDK excludes of its own accord, for every application at once.

## v0.2.1

- An application that logs through `rails_semantic_logger` stamps its lines with the destination
  Kamal deployed to, the environment its metrics and its errors already report. Semantic Logger
  takes that field from `RAILS_ENV`, which every destination of an application runs as, so a
  staging container's logs read as production.

  The gem sets it before the application is configured, so an application that names its own
  `config.semantic_logger.environment` keeps it. Semantic Logger is neither loaded nor depended on
  here: an application that logs another way is unchanged.

## v0.2.0

- A `sidekiq` collector, beside `puma` and `solid_queue`. A process the `sidekiq` command started
  reports it without a deploy saying so, and `CLOUDWATCH_METRICS_COLLECT` names it where a process
  is something else.

  It reports the Solid Queue collector's four names, meaning the same thing in the same unit, so
  every alarm and dashboard already built on them covers an application that runs its jobs under
  Sidekiq: `QueueDepth`, `OldestReadyJobAge`, `FailedJobs` and `SupervisorHeartbeatAge`. Beside
  them, `ScheduledJobs`, `Processes` and `BusyWorkers`.

  `FailedJobs` is the retry set and the dead set together, not the number Sidekiq keeps under that
  name, which is every job that has ever failed and so only climbs. `SupervisorHeartbeatAge` is the
  newest beat of a process on this host, because Sidekiq has no supervisor over them to ask and a
  role spread over a pair of hosts must not have a dead half of it covered for by the live one.
  `Processes` and `BusyWorkers` count every host, being facts about the queue rather than the host.

  The gem takes no dependency on sidekiq. The collector asks whether the process has one, and asks
  it for `sidekiq/api`, which a process that runs jobs does not otherwise load.
- `railties >= 6.1`, so an application on Rails 6.1 reports its metrics and its errors. Each
  instrumentation in the Rails bundle patches Rails 7.1 and up and says so itself, so that
  application traces nothing of the request and is told what went uninstalled.

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
