# What an app's own base controller does for its MCP tools: the gem leaves
# sign-in, rate limits and the Origin check to the app.
class Mcp::BaseController < ActionController::API
  include StatelessMcp::Rails::Controller

  before_action :refuse_cross_origin

  private

  # A page in a browser must not drive the tools with someone's credentials.
  def refuse_cross_origin
    head :forbidden if request.origin.present? && request.origin != request.base_url
  end
end
