# app/models/mcp_oauth_storage.rb
class McpOAuthStorage < StatelessMcp::OAuth::Storage
  def issue_token(claims)
    encryptor.encrypt_and_sign(claims, purpose: :mcp_oauth_token)
  end

  # Only the grant's newest refresh token can be used, so the grant notes its id.
  def issue_tokens(access, refresh)
    McpGrant.where(id: refresh[:grant_id]).update_all(refresh_token_id: refresh[:id])
    super
  end

  def read_token(token)
    encryptor.decrypt_and_verify(token, purpose: :mcp_oauth_token)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  # Only the grant's newest refresh token can be used, and only once.
  def consume_refresh_token(claims)
    McpGrant.where(id: claims[:grant_id], refresh_token_id: claims[:id], revoked_at: nil)
            .update_all(refresh_token_id: nil) == 1
  end

  private
    # A separate key, derived from the app's secret_key_base.
    def encryptor
      @encryptor ||= ActiveSupport::MessageEncryptor.new(
        Rails.application.key_generator.generate_key("mcp oauth tokens", 32),
        cipher: "aes-256-gcm", serializer: :json, url_safe: true
      )
    end
end
