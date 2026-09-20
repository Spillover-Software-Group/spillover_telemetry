# frozen_string_literal: true

require "support/sidekiq_runtime"

# What `require "sidekiq/api"` adds to a process that has Sidekiq, as far as the collector reads it.
# The collector's own require is what loads this file; see test/support/sidekiq_runtime.rb for why
# it can.
#
# Every one of these answers out of Redis in the real thing, so each answers here from what the test
# running set, and the shapes are Sidekiq's own: a queue with nothing in it has a latency of 0
# rather than of no seconds at all, and a process carries how many of its threads are busy, when it
# last beat as seconds since the epoch, and the host it runs on.
module Sidekiq
  class Stats
    def enqueued = SidekiqRuntime.numbers.fetch(:enqueued)
    def scheduled_size = SidekiqRuntime.numbers.fetch(:scheduled)
    def retry_size = SidekiqRuntime.numbers.fetch(:retrying)
    def dead_size = SidekiqRuntime.numbers.fetch(:dead)
  end

  class Queue
    def self.all = SidekiqRuntime.numbers.fetch(:latencies).map { |latency| new(latency) }

    attr_reader :latency

    def initialize(latency)
      @latency = latency
    end
  end

  class ProcessSet
    include Enumerable

    def each(&block) = SidekiqRuntime.numbers.fetch(:processes).each(&block)
  end
end
