# AGENTS.md

Guidance for coding agents working in this repository. `CLAUDE.md` is a symlink to this file.
`README.md` is for someone using the gem; this is for whoever has to change it.

## What this is

One gem for the three things every Spillover Rails application does to report on itself. It replaced
a `lib/runtime_metrics.rb` and two initializers that were copied into each application and drifted.
The point of it is that there is now one copy, so nothing here may name an application, a metric
namespace, a DSN, a service or an environment. Everything specific comes from the caller or from a
variable the deploy sets.

## Invariants

Alarms, dashboards, Sentry projects and traces are built on these. Changing one is a change to
production monitoring, not a refactor.

**Metrics**

- The metric names and their units are what `Metrics::UNITS` says. A rename breaks every alarm and
  dashboard that reads it. Two collectors may report one name, and where they do it is the same
  measurement in the same unit: an alarm reads a name, not a collector.
- The dimension set is exactly `App`, `Environment`, `Role`, in that order.
- One document per process per 60 seconds.
- The document is written as one whole line to the stream, never through a logger, which would bury
  it in a message field. It is generated with `JSON.generate`, not `to_json`: in a Rails process
  `to_json` is Active Support's encoder.
- A failure is logged once with `logger.warn` and never raised, and the same failure is not repeated
  until it changes.
- The sampler's thread has `report_on_exception` off and is stopped `at_exit`.
- A console, a runner and a rake task report nothing, **including in a container whose environment
  names collectors**. The process decides whether it reports and `CLOUDWATCH_METRICS_COLLECT` decides
  what, never the other way round: a container passes the same environment to everything it starts.
- A query the sampler makes goes through `with_connection`. Its thread lives as long as the process,
  and Active Record keeps a connection with the thread that asked until it is given back. **The suite
  cannot catch a regression here**: one connection serves the whole run, so a test passes either way.
  Prove it outside the harness, with `bin/rails runner`.

**Errors**

- Nothing is sent without `SENTRY_DSN`. `Sentry.init` never runs, the SDK stays uninitialized, and
  the middleware sentry-rails inserts passes every request through untouched.
- `Sentry.init` sets the DSN, the environment and the release, and nothing else it does not have to,
  so `send_default_pii` stays off. Anything more belongs in an application's own
  `config.spillover_telemetry.sentry`, never in a second `Sentry.init`.
- **An error says of its request only the method and the URL.** The headers are the one part of
  it `send_default_pii` off leaves in, so `data_collection.http_headers.request` is off beside it.
- **sentry-rails' structured logging is off.** Left alone it forwards every Active Record and Action
  Controller log line to Sentry. The logs already go to CloudWatch, Sentry is where errors go, and a
  second copy of the SQL and the controller timings is traffic and cost nobody asked for. It is set
  before the application's own block, so an application that wants it can turn it back on.

**Traces**

- No OpenTelemetry constant is defined in a process without `OTEL_EXPORTER_OTLP_ENDPOINT`. The gems
  are required inside `Traces.install` for that reason, never at load.
- The bundle is installed with `use_all`. Naming the Rails instrumentation alone installs an empty
  umbrella: no middleware, no spans.
- Active Record is left out and `/health` is untraced.
- The Faraday and HTTPX instrumentations are required beside the Rails bundle and gated by nothing
  here. Each one's own `present` block asks whether the client is defined and HTTPX's `compatible`
  block asks whether the version is one it patches; the registry logs what it skipped and raises
  nothing. A constant check in this gem would be a second copy of that, drifting from the version
  the instrumentation actually supports.
- The service name is never set in code. `OTEL_SERVICE_NAME` is the SDK's own variable, and a
  container that forgets it reporting as `unknown_service` is better than one quietly counted as
  another application.

**The log**

- Semantic Logger is never loaded or depended on here. `config.semantic_logger` is the
  `SemanticLogger` module itself, so the environment is set on it directly and only where the
  application has loaded it.
- It is set in `before_configuration`, which runs as the application class is opened, before its
  application file, its environment files and its initializers. That ordering is the whole of how an
  application's own `config.semantic_logger.environment` wins: there is no flag and no comparison,
  only a value the application is free to write after. An initializer would be too late and would
  silently take an application's environment away from it.

## Where things live

| File | What it holds |
|---|---|
| `lib/spillover_telemetry/settings.rb` | Every environment variable, read once |
| `lib/spillover_telemetry/metrics.rb` | The document, the sampler, the collector registry |
| `lib/spillover_telemetry/metrics/*_collector.rb` | One runtime each: `available?` and `values(now)` |
| `lib/spillover_telemetry/errors.rb` | `Sentry.init` |
| `lib/spillover_telemetry/traces.rb` | The SDK configuration |
| `lib/spillover_telemetry/railtie.rb` | The only Rails-aware file: when each of the three runs, and the log's environment |

The three signal files take their settings as arguments and know nothing of Rails, which is what
makes them testable without booting anything. The Railtie is where `Rails.env`, `Rails.logger` and
the process's own shape are read.

Its install runs `after: :load_config_initializers`: late enough for an application's own
initializers to have set an extension point, early enough that Sentry's middleware and
OpenTelemetry's are in the stack Rails builds after it. The sampler starts in `after_initialize`,
because a collector reads the application's models.

## Verifying a change

```shell
bin/check && bin/test
```

Both are judged by exit code. There is no CI: the organisation has no Actions budget.

The suite runs inside `test/dummy`, because Solid Queue's models belong to an engine and an engine's
models are loaded by the application that mounts it. That boot sets no telemetry variable, so it
installs nothing.

**What a variable does is tested by a probe**, in a process of its own (`test/support/probe.rb`,
`test/dummy/probe.rb`): every switch is read once at boot, a process can only be one thing, and "no
OpenTelemetry constant at all" is only true of a process that never had one. A probe writes its
report to a file rather than stdout, because boot writes to stdout too.

Collectors are tested against the real runtime wherever the runtime can be had in a process: a Puma
server on an ephemeral port, and Solid Queue's own schema in SQLite. So are the HTTP clients: a
probe makes a real request to a Puma server the test started, and reports the spans out of an
in-memory exporter.

Sidekiq is the one that cannot be. Every number it reports it reports out of Redis, and the suite
has none, so `test/support/sidekiq/api.rb` stands in for the three classes the collector reads and
answers what the test running set. It is a file rather than a constant a test defines, because the
collector's own `require "sidekiq/api"` is what loads it, from the load path
`test/support/sidekiq_runtime.rb` puts `test/support` on. A collector that stopped asking for
Sidekiq's read side would find nothing to read, which is how that require is covered.

## Releasing

Tag `vX.Y.Z` after `bin/check && bin/test`, add the section to `CHANGELOG.md`, then move each
application's Gemfile to the new tag. Applications pin a tag and never float, which is the lesson
from `frontend-shared`.

A breaking change here is one that changes a metric name, a unit, the dimension set or a default
above. It is a major version and a deploy of every application that takes the gem.
