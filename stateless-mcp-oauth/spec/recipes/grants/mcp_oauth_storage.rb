# app/models/mcp_oauth_storage.rb
class McpOAuthStorage < StatelessMcp::OAuth::Storage
  # The grant takes the authorization code's id. insert skips an id that's
  # taken, returning no rows, so each authorization code creates at most one
  # grant. This app approves with user_id.
  def create_grant(code_id:, authorization_request:, approved_by:)
    code_id if McpGrant.insert({ id: code_id, **authorization_request, user_id: approved_by[:user_id] }).any?
  end

  def find_grant(id)
    McpGrant.find_by(id:, revoked_at: nil)
  end

  def revoke_grant(id)
    McpGrant.where(id:).update_all(revoked_at: Time.current)
  end
end
