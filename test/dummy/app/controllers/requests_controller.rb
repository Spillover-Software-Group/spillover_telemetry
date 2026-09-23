# frozen_string_literal: true

# A request an application fails in, for the probes that ask what the error says about it.
class RequestsController < ActionController::API
  def failure
    raise "The request failed"
  end
end
