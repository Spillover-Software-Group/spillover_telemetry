# frozen_string_literal: true

# The smallest schema an operation can be executed against: one field, so that the trace of a request
# to /graphql has a query in it.
class DummySchema < ::GraphQL::Schema
  class QueryType < ::GraphQL::Schema::Object
    field :greeting, String, null: false

    def greeting
      "hello"
    end
  end

  query QueryType
end
