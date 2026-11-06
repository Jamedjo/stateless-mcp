# app/controllers/mcp_authorizations_controller.rb
class McpAuthorizationsController < ApplicationController
  before_action :authenticate_user! # the app's sign-in
  before_action :load_authorization

  def new
  end

  def create
    url = params[:decision] == "approve" ? @authorization.approve(user_id: current_user.id) : @authorization.deny
    redirect_to url, allow_other_host: true
  end

  private
    # If the client or redirect URI can't be trusted, show the error to the
    # person and don't redirect. Send any other problem to the client.
    def load_authorization
      @authorization = MCP_OAUTH_SERVER.authorization_request(params)
      redirect_to @authorization.error_redirect_url, allow_other_host: true if @authorization.problem
    rescue StatelessMcp::OAuth::Error => error
      render plain: error.message, status: :bad_request
    end
end
