# app/models/mcp_oauth_storage.rb
class McpOAuthStorage < StatelessMcp::OAuth::Storage
  # New tokens are stored as rows. Encrypted ones keep working until they
  # expire or are refreshed.
  def read_token(token)
    McpToken.find_by(digest: McpToken.digest(token), revoked_at: nil)&.claims || read_encrypted_token(token)
  end

  def consume_refresh_token(claims)
    return consume_encrypted_refresh_token(claims) unless McpToken.exists?(token_id: claims[:id])
    McpToken.where(token_id: claims[:id], used_at: nil, revoked_at: nil).update_all(used_at: Time.current) == 1
  end

  # An encrypted token has no row, so its grant is revoked instead.
  def revoke_token(claims)
    super if McpToken.where(token_id: claims[:id]).update_all(revoked_at: Time.current).zero?
  end
end
