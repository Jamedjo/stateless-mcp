# app/models/mcp_oauth_storage.rb
class McpOAuthStorage < StatelessMcp::OAuth::Storage
  def read_token(token)
    McpToken.find_by(digest: McpToken.digest(token), revoked_at: nil)&.claims || doorkeeper_claims(token)
  end

  private
    def doorkeeper_claims(token)
      if (row = Doorkeeper::AccessToken.by_token(token))
        doorkeeper_claims_for(row, kind: "access", expires_at: row.expires_at) unless row.revoked?
      elsif (row = Doorkeeper::AccessToken.by_refresh_token(token))
        doorkeeper_claims_for(row, kind: "refresh", expires_at: row.created_at + 30.days)
      end
    end

    # One grant per application and person, made the first time it's seen.
    def doorkeeper_claims_for(row, kind:, expires_at:)
      grant_id = "doorkeeper-#{row.application_id}-#{row.resource_owner_id}"
      create_grant(code_id: grant_id,
                   authorization_request: { client_id: row.application.uid, resource: "https://notes.example/mcp", scope: row.scopes.to_s },
                   approved_by: { user_id: row.resource_owner_id })
      { kind:, id: "doorkeeper-#{kind}-#{row.id}", grant_id:, expires_at: expires_at.to_i, doorkeeper_id: row.id }
    end
end
