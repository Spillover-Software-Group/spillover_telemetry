# frozen_string_literal: true

require "solid_queue"

# Solid Queue's own tables, taken from the gem that owns them, so the queue collector is measured
# against the schema it will meet rather than against one written here. The day that path moves,
# this fails loudly rather than testing a table of its own making.
module QueueSchema
  PATH = ::SolidQueue::Engine.root.join("lib/generators/solid_queue/install/templates/db/queue_schema.rb")

  def self.load
    ::ActiveRecord::Schema.verbose = false
    Kernel.load(PATH)
  end
end
