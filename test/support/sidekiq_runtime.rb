# frozen_string_literal: true

# Where the collector's own `require "sidekiq/api"` finds sidekiq/api.rb beside this file.
$LOAD_PATH.unshift(__dir__) unless $LOAD_PATH.include?(__dir__)

# A process with Sidekiq in it, as the collector sees one. Sidekiq keeps every number it reports in
# Redis and the suite has none, so the runtime here is the constant and the three classes the
# collector reads, and nothing below them.
#
# `require "sidekiq"` defines the constant and no more, so that is all a test starts with: the
# classes come from `sidekiq/api`, which the collector asks for itself. A collector that stopped
# asking would find nothing to read and every test here would say so.
#
# The runtime is claimed for the length of a test and given back afterwards, the way a Puma server
# is, because `available?` asks whether the constant exists and "no Sidekiq in this process" is only
# true of a process where nothing defined one.
module SidekiqRuntime
  # A process is what Sidekiq's process set yields: how many of its threads are busy, when it last
  # beat, and the host it runs on, under the keys Sidekiq gives them.
  NOTHING = { enqueued: 0, latencies: [], scheduled: 0, retrying: 0, dead: 0, processes: [] }.freeze

  class << self
    # What the classes in sidekiq/api.rb answer, which is what the test running put here.
    attr_accessor :numbers

    def claim(**numbers)
      self.numbers = NOTHING.merge(numbers)
      # The same module every time: Sidekiq's read side is loaded into it once, by the first
      # collector to ask, and a later claim wants that module rather than an empty one.
      ::Object.const_set(:Sidekiq, @sidekiq ||= Module.new)
    end

    def release
      self.numbers = nil
      ::Object.send(:remove_const, :Sidekiq) if ::Object.const_defined?(:Sidekiq)
    end
  end

  def run_sidekiq(**numbers)
    SidekiqRuntime.claim(**numbers)
  end

  def after_teardown
    super
    SidekiqRuntime.release
  end
end
