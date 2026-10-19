# app/models/mcp_oauth_storage.rb
class McpOAuthStorage < StatelessMcp::OAuth::Storage
  # A random token, kept only as its digest.
  def issue_token(claims)
    token = SecureRandom.urlsafe_base64(32)
    McpToken.create!(digest: McpToken.digest(token), token_id: claims[:id], mcp_grant_id: claims[:grant_id],
                     kind: claims[:kind], expires_at: Time.at(claims[:expires_at]),
                     authorization_request: claims[:authorization_request], approved_by: claims[:approved_by])
    token
  end

  def read_token(token)
    McpToken.find_by(digest: McpToken.digest(token), revoked_at: nil)&.claims
  end

  # A used refresh token's row is marked used, not revoked, so it still reads
  # and the gem can tell when it's used again.
  def consume_refresh_token(claims)
    McpToken.where(token_id: claims[:id], used_at: nil, revoked_at: nil).update_all(used_at: Time.current) == 1
  end

  def revoke_token(claims)
    McpToken.where(token_id: claims[:id]).update_all(revoked_at: Time.current)
  end
end
