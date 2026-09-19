# frozen_string_literal: true

# Every test rolled back, so a test reads only the rows it wrote. One connection serves the whole
# run, which is also what hides the queue collector's `with_connection` here: a test of it would pass
# either way, which is why the collector says so in a comment instead.
module Transactional
  def before_setup
    super
    ::ActiveRecord::Base.connection.begin_transaction(joinable: false)
  end

  def after_teardown
    ::ActiveRecord::Base.connection.rollback_transaction
    super
  end
end
