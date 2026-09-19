# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# The suite runs inside the dummy application, because Solid Queue's models belong to an engine and
# an engine's models are loaded by the application that mounts it. No telemetry variable is set for
# this boot, so it installs nothing: what a variable does is tested by a probe, in a process of its
# own. See test/support/probe.rb.
directory = Dir.mktmpdir("spillover-telemetry")
at_exit { FileUtils.remove_entry(directory, true) }

ENV["RAILS_ENV"] = "test"
ENV["DUMMY_DATABASE"] = File.join(directory, "queue.sqlite3")

require_relative "dummy/config/environment"
require_relative "support/queue_schema"

require "minitest/autorun"

QueueSchema.load

ActiveSupport::TestCase.test_order = :random
