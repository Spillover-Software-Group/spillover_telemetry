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
  dashboard that reads it.
- The dimension set is exactly `App`, `Environment`, `Role`, in that order.
- One document per process per 60 seconds.
- The document is written as one whole line to the stream, never through a logger, which would bury
  it in a message field. It is generated with `JSON.generate`, not `to_json`: in a Rails process
  `to_json` is Active Support's encoder.
- A failure is logged once with `logger.warn` and never raised, and the same failure is not repeated
  until it changes.
- The sampler's thread has `report_on_exception` off and is stopped `at_exit`.
- A console, a runner and a rake task report nothing.
- A query the sampler makes goes through `with_connection`. Its thread lives as long as the process,
  and Active Record keeps a connection with the thread that asked until it is given back. **The suite
  cannot catch a regression here**: one connection serves the whole run, so a test passes either way.
  Prove it outside the harness, with `bin/rails runner`.

**Errors**

- Nothing is sent without `SENTRY_DSN`. `Sentry.init` never runs, the SDK stays uninitialized, and
  the middleware sentry-rails inserts passes every request through untouched.
- `Sentry.init` sets the DSN, the environment and the release, and nothing else, so
  `send_default_pii` stays off. Anything more belongs in an application's own
  `config.spillover_telemetry.sentry`, never in a second `Sentry.init`.

**Traces**

- No OpenTelemetry constant is defined in a process without `OTEL_EXPORTER_OTLP_ENDPOINT`. The gems
  are required inside `Traces.install` for that reason, never at load.
- The bundle is installed with `use_all`. Naming the Rails instrumentation alone installs an empty
  umbrella: no middleware, no spans.
- Active Record is left out and `/health` is untraced.
- The service name is never set in code. `OTEL_SERVICE_NAME` is the SDK's own variable, and a
  container that forgets it reporting as `unknown_service` is better than one quietly counted as
  another application.

## Where things live

| File | What it holds |
|---|---|
| `lib/spillover_telemetry/settings.rb` | Every environment variable, read once |
| `lib/spillover_telemetry/metrics.rb` | The document, the sampler, the collector registry |
| `lib/spillover_telemetry/metrics/*_collector.rb` | One runtime each: `available?` and `values(now)` |
| `lib/spillover_telemetry/errors.rb` | `Sentry.init` |
| `lib/spillover_telemetry/traces.rb` | The SDK configuration |
| `lib/spillover_telemetry/railtie.rb` | The only Rails-aware file: when each of the three runs |

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

Collectors are tested against the real runtime, never against a stand-in: a Puma server on an
ephemeral port, and Solid Queue's own schema in SQLite.

## Releasing

Tag `vX.Y.Z` after `bin/check && bin/test`, add the section to `CHANGELOG.md`, then move each
application's Gemfile to the new tag. Applications pin a tag and never float, which is the lesson
from `frontend-shared`.

A breaking change here is one that changes a metric name, a unit, the dimension set or a default
above. It is a major version and a deploy of every application that takes the gem.
