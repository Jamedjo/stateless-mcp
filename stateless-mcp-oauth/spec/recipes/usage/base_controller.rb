# app/controllers/mcp/base_controller.rb
class Mcp::BaseController < ActionController::API
  include StatelessMcp::Rails::Controller

  # Every request here has a valid access token. mcp_grant says who approved,
  # such as mcp_grant.user_id.
end
