# frozen_string_literal: true

# A request an application answers, one it fails in, and one that executes a GraphQL operation. Each
# names its user first, as an application does where it authenticates, from what the request
# carried: here the query string stands in for a token. Each says on its way out which trace it was
# in, as an application says on its log lines.
class RequestsController < ActionController::API
  before_action :authenticate
  after_action :name_trace

  def answer
    SpilloverTelemetry.annotate(operation: "answer")
    head :ok
  end

  def failure
    raise "The request failed"
  end

  def graphql
    render json: DummySchema.execute(params[:query], operation_name: params[:operationName])
  end

  private
    def authenticate
      return unless params[:id]

      SpilloverTelemetry.identify_user(id: params[:id], email: params[:email])
      SpilloverTelemetry.annotate(account_id: params[:id])
    end

    def name_trace
      trace_id = SpilloverTelemetry.trace_id
      response.headers["Trace-Id"] = trace_id if trace_id
    end
end
