# app/models/mcp_token.rb
class McpToken < ApplicationRecord
  # An authorization code's row is written before its grant exists.
  belongs_to :mcp_grant, optional: true

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def claims
    { kind:, id: token_id, grant_id: mcp_grant_id, expires_at: expires_at.to_i, authorization_request:, approved_by: }
  end
end
