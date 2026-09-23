# frozen_string_literal: true

# A request an application answers and one it fails in. Each names its user first, as an application
# does where it authenticates, from what the request carried: here the query string stands in for a
# token.
class RequestsController < ActionController::API
  before_action :authenticate

  def answer
    head :ok
  end

  def failure
    raise "The request failed"
  end

  private
    def authenticate
      SpilloverTelemetry.identify_user(id: params[:id], email: params[:email]) if params[:id]
    end
end
