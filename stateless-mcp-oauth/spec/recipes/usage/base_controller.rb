# app/controllers/mcp/base_controller.rb
class Mcp::BaseController < ActionController::API
  include StatelessMcp::Rails::Controller

  before_action :require_mcp_token

  private
    # The grant says who approved, such as @mcp_grant.user_id.
    def require_mcp_token
      @mcp_grant = MCP_OAUTH.verified_grant(request)
      head :unauthorized, MCP_OAUTH.unauthorized_headers(invalid_token: request.authorization.present?) unless @mcp_grant
    end
end
