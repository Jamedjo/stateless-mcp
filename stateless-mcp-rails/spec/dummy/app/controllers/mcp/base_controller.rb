# What an app's own base controller does for its MCP tools: the gem leaves
# sign-in and rate limits to the app.
class Mcp::BaseController < ActionController::API
  include StatelessMcp::Rails::Controller

  # Stands in for the app's sign-in, so the specs can show it runs first.
  before_action { head :forbidden if request.headers["X-Refuse"] }
  # Only for callers that name themselves, so the specs can reach the limit
  # without sharing a count.
  rate_limit to: 2, within: 1.minute, by: -> { request.headers["X-Caller"] }, store: ActiveSupport::Cache::MemoryStore.new, if: -> { request.headers["X-Caller"] }
end
