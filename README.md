# spillover_telemetry

How a Spillover Rails application reports on itself: **runtime metrics** on stdout, **errors** to
Sentry, and **traces** to an OTLP endpoint.

Each signal is off until the deploy sets its one variable, and an application that adds the gem
writes no configuration at all.

## Installing it

```ruby
# Gemfile
gem "spillover_telemetry", github: "Spillover-Software-Group/spillover_telemetry", tag: "v0.2.0"
```

Pinned to a tag, never floating. The repository is public, so the image build's `bundle install`
clones it without a credential.

The gem carries `sentry-rails` and five OpenTelemetry gems, the SDK, the OTLP exporter and one
instrumentation each for Rails, Faraday and httpx, so those lines come out of the Gemfile. Bundler
requires what a Gemfile names and never a gem's own dependencies, so OpenTelemetry is still loaded
only where an endpoint is set.

Then set what the container should report, in `config/deploy.yml`:

```yaml
env:
  clear:
    CLOUDWATCH_METRICS_NAMESPACE: Spillover/Runtime
    CLOUDWATCH_METRICS_APP: my-reviews-api
    CLOUDWATCH_METRICS_ROLE: web
    OTEL_EXPORTER_OTLP_ENDPOINT: http://host.docker.internal:4318
    OTEL_SERVICE_NAME: my-reviews-api
  secret:
    - SENTRY_DSN
```

That is the whole of it.

## What it reports

### Runtime metrics

One CloudWatch Embedded Metric Format document a minute, written as a whole line to stdout. The log
driver ships stdout and CloudWatch reads the fields under `_aws` as metrics, so there is no agent,
no SDK and no network call. Every metric carries the dimensions `App`, `Environment` and `Role`.

| Collector | Reports | Unit | Where it comes from |
|---|---|---|---|
| `puma` | `PumaBacklog` | Count | requests waiting for a thread; in a clustered Puma, summed over the workers |
| | `PumaPoolCapacity` | Count | threads that could still take one |
| | `PumaRunningThreads` | Count | threads running |
| `sidekiq` | `QueueDepth` | Count | jobs waiting to run, across every queue |
| | `OldestReadyJobAge` | Seconds | how long the oldest of them has waited |
| | `FailedJobs` | Count | jobs waiting to be tried again, and jobs out of tries |
| | `SupervisorHeartbeatAge` | Seconds | how long ago a process on this host last beat |
| | `ScheduledJobs` | Count | jobs held to run later |
| | `Processes` | Count | Sidekiq processes working the queue, on every host |
| | `BusyWorkers` | Count | threads those processes are busy in |
| `solid_queue` | `QueueDepth` | Count | jobs waiting to run |
| | `OldestReadyJobAge` | Seconds | how long the oldest of them has waited |
| | `FailedJobs` | Count | jobs that have given up |
| | `SupervisorHeartbeatAge` | Seconds | how long ago this host's supervisor last beat |

A value with nothing to measure yet is left out rather than reported as zero, and a collector whose
runtime is not in this process reports nothing at all. Where two collectors report the same name it
is the same measurement in the same unit, so one alarm and one dashboard cover a queue whichever
runtime is behind it, and an application that changes runtime is watched by what is already built.

The two queues answer those four from different places. Sidekiq's `FailedJobs` is its retry set and
its dead set together, the jobs that have failed and are waiting to be tried again or have run out
of tries. It is not the number Sidekiq keeps under that name, which is every job that has ever
failed, counted since its Redis was last emptied, so it only climbs and an alarm on it fires once
and never clears. Sidekiq's `SupervisorHeartbeatAge` is the newest beat of a process on this host,
because every Sidekiq process beats for itself and there is no supervisor over them to ask; it is
narrowed to this host for the same reason the Solid Queue one is, so that a role spread over a pair
of hosts does not have a dead half of it covered for by the live one. Where nothing is beating here
there is no age to report, which leaves the alarm to its missing-data rule.

`Processes` and `BusyWorkers` are not narrowed that way. How much is working the queue is a fact
about the queue, the way its depth is, so both hosts report the same pair of numbers.

### Errors

`Sentry.init` with the DSN, the environment and the release, so `send_default_pii` stays off. Where
`httpx` is loaded, Sentry's own adapter for it is required, and an outbound call becomes a breadcrumb
on whatever error follows it.

sentry-rails' structured logging is turned off. Its default forwards every Active Record and Action
Controller log line to Sentry, and those logs already go to CloudWatch. An application that wants it
turns it back on in its own `sentry` block.

### Traces

The OpenTelemetry SDK, covering the request that comes in and the calls the application makes out.

| Instrumentation | Traces | Where it installs |
|---|---|---|
| The Rails bundle | the request, through Rack, Action Pack, Action View, Active Job and Active Support | where the process is on Rails 7.1 or newer, `/health` excepted |
| Faraday | one client span per outbound call | where the process loaded Faraday 1.0 or newer |
| httpx | one client span per outbound call | where the process loaded httpx 1.6 or newer |

Active Record is left out of the bundle: it traces transactions and nothing else, and a job process
polling its queue is a transaction a second. The health check is the load balancer asking every
fifteen seconds, and answers nothing a trace could add to.

An application adds no client instrumentation gem of its own. Both are carried here, neither loads
its client, and each asks the process whether it has one: a process with neither client, or with an
httpx older than the instrumentation patches, is told so in a line of its own and traces everything
else. The service name comes from `OTEL_SERVICE_NAME`, the SDK's own variable: a container that
forgets it reports as `unknown_service`.

Each instrumentation in the Rails bundle patches Rails 7.1 and up and asks the process which it is
on, the same way. An application older than that reports its metrics and its errors as any other
does, is told in a line of its own what went uninstalled, and traces nothing of the request.

## The variables

| Variable | What it does |
|---|---|
| `CLOUDWATCH_METRICS_NAMESPACE` | The switch for metrics, and the namespace they land in |
| `CLOUDWATCH_METRICS_APP` | The `App` dimension. Required where the namespace is set |
| `CLOUDWATCH_METRICS_ROLE` | The `Role` dimension. Required where the namespace is set |
| `CLOUDWATCH_METRICS_COLLECT` | The collectors to report from, comma separated, where the default is wrong |
| `SENTRY_DSN` | The switch for errors, and where they go |
| `SENTRY_ENVIRONMENT` | The environment errors are reported as, where it is not the destination |
| `KAMAL_DESTINATION` | The environment metrics and errors are reported as. Kamal sets it to the destination; a process outside a container reports as `Rails.env` |
| `KAMAL_VERSION` | The release errors are reported against. Kamal sets it to the commit |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | The switch for traces, and where they go |
| `OTEL_SERVICE_NAME` | The service traces are attributed to |

A variable that is set to nothing counts as one that is not set.

### Which collectors a process reports from

A container passes the same environment to every process it starts, so the process is read from what
it is: a Rails server reports `puma`, a Solid Queue supervisor started by `bin/jobs` reports
`solid_queue`, a worker started by `sidekiq` reports `sidekiq`, and a console, a runner or a rake
task reports nothing rather than printing a document a minute into someone's terminal.

The one case that cannot be read from outside is a server that runs the queue inside itself
(`SOLID_QUEUE_IN_PUMA`). That role says so:

```yaml
CLOUDWATCH_METRICS_COLLECT: puma,solid_queue
```

It says *what* a reporting process reports, never *whether* one reports: the console in that same
container sees the variable too, and still says nothing.

## The two extension points

An application that needs more than the defaults adds to them rather than repeating them.

```ruby
# config/application.rb
config.spillover_telemetry.sentry = ->(sentry) { sentry.traces_sample_rate = 0.1 }

config.spillover_telemetry.instrumentation = {
  "OpenTelemetry::Instrumentation::ActiveRecord" => { enabled: true }
}
```

The first is called with the Sentry configuration inside `Sentry.init`, after the DSN, environment
and release, so an application never writes a second `Sentry.init` and loses them. The second is
merged over the gem's own instrumentation options by name: a name it names, it owns outright.

## Adding a collector

A collector is a class with three things:

```ruby
module SpilloverTelemetry
  class Metrics
    class ResqueCollector
      UNITS = { "QueueDepth" => "Count" }.freeze

      # Whether this process can see the runtime at all.
      def available?
        Object.const_defined?(:Resque)
      end

      # What it reads from it now. A number with nothing to measure yet is nil.
      def values(_now)
        { "QueueDepth" => ::Resque.size("default") }
      end
    end
  end
end
```

Add it to `Metrics::COLLECTORS` under the name a deploy would ask for, and nothing else needs to know
it exists. `UNITS` is what the document declares each value with, so a name missing from it raises
rather than reaching CloudWatch as a bare number, and a name another collector already reports has to
mean the same thing in the same unit.

A process that a deploy should not have to name is read in `Railtie.collectors_for_this_process`,
from what started it.

## Working on it

```shell
mise install    # Ruby, as mise.toml pins it
bin/setup       # bundle install
bin/check       # RuboCop, read-only
bin/test        # the whole suite, or the files named as arguments
```

`bin/check && bin/test` is the gate, judged by exit code. There is no CI.
