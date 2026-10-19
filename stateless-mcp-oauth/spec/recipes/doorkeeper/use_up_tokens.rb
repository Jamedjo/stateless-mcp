# app/models/mcp_oauth_storage.rb
class McpOAuthStorage < StatelessMcp::OAuth::Storage
  def consume_refresh_token(claims)
    if claims[:doorkeeper_id]
      Doorkeeper::AccessToken.where(id: claims[:doorkeeper_id], revoked_at: nil).update_all(revoked_at: Time.current) == 1
    else
      McpToken.where(token_id: claims[:id], used_at: nil, revoked_at: nil).update_all(used_at: Time.current) == 1
    end
  end

  def revoke_token(claims)
    if claims[:doorkeeper_id]
      Doorkeeper::AccessToken.where(id: claims[:doorkeeper_id]).update_all(revoked_at: Time.current)
    else
      McpToken.where(token_id: claims[:id]).update_all(revoked_at: Time.current)
    end
  end
end
