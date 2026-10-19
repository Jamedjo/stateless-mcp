require "active_record"
require "active_support/message_encryptor"
require "tmpdir"
require_relative "support/oauth_recipes"

# The ActiveRecord recipes in docs/oauth-storage.md and
# docs/oauth-storage-moving.md, run against SQLite.
RSpec.describe "The OAuth storage recipes" do
  # A database file, since the race examples need database connections from several threads.
  before(:all) do
    @dir = Dir.mktmpdir
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: File.join(@dir, "oauth.sqlite3"), pool: 10, timeout: 5000)
    OAuthRecipes.migrate(OAuthRecipes::Encrypted::CreateMcpGrants, OAuthRecipes::Encrypted::AddRefreshTokenIdToMcpGrants, OAuthRecipes::TokenRows::CreateMcpTokens)
  end

  after(:all) do
    ActiveRecord::Base.remove_connection
    FileUtils.remove_entry(@dir)
  end

  def access(grant_id, id: SecureRandom.uuid)
    { kind: "access", id:, grant_id:, expires_at: Time.now.to_i + 3600 }
  end

  def refresh(grant_id, id: SecureRandom.uuid)
    { kind: "refresh", id:, grant_id:, expires_at: Time.now.to_i + 3600 }
  end

  def symbolize(claims)
    StatelessMcp::OAuth::Claims.symbolize(claims)
  end

  describe "encrypted tokens" do
    let(:storage) { OAuthRecipes::Encrypted::McpOAuthStorage.new }

    it_behaves_like "stateless-mcp oauth storage" do
      let(:approved_by) { { user_id: 42 } }
    end

    it "stores nothing for an access token" do
      expect { storage.issue_token(access("g")) }.not_to change { OAuthRecipes::TokenRows::McpToken.count }
    end

    it "accepts only the grant's newest refresh token" do
      storage.create_grant(code_id: "newest", authorization_request: { client_id: "c", resource: "r", scope: "s" }, approved_by: { user_id: 1 })
      older = symbolize(storage.read_token(storage.issue_tokens(access("newest"), refresh("newest")).last))
      newer = symbolize(storage.read_token(storage.issue_tokens(access("newest"), refresh("newest")).last))

      expect(storage.consume_refresh_token(older)).to be(false)
      expect(storage.consume_refresh_token(newer)).to be(true)
    end
  end

  describe "token rows" do
    let(:storage) { OAuthRecipes::TokenRows::McpOAuthStorage.new }

    it_behaves_like "stateless-mcp oauth storage" do
      let(:approved_by) { { user_id: 42 } }
    end

    it "keeps a digest, never the token" do
      token = storage.issue_token(access("g"))

      expect(OAuthRecipes::TokenRows::McpToken.where(digest: Digest::SHA256.hexdigest(token))).to exist
      expect(OAuthRecipes::TokenRows::McpToken.pluck(:digest)).not_to include(token)
    end

    it "revokes one token, leaving its grant" do
      storage.create_grant(code_id: "kept", authorization_request: { client_id: "c", resource: "r", scope: "s" }, approved_by: { user_id: 1 })
      token = storage.issue_token(refresh("kept"))

      storage.revoke_token(symbolize(storage.read_token(token)))

      expect(storage.read_token(token)).to be_nil
      expect(storage.find_grant("kept")).not_to be_nil
    end
  end

  describe "switching from encrypted tokens to token rows" do
    let(:storage) { OAuthRecipes::Switching::McpOAuthStorage.new }
    let(:before_switch) { OAuthRecipes::Encrypted::McpOAuthStorage.new }

    it_behaves_like "stateless-mcp oauth storage" do
      let(:approved_by) { { user_id: 42 } }
    end

    it "stores new tokens as rows, and still reads and refreshes older encrypted tokens" do
      storage.create_grant(code_id: "switching", authorization_request: { client_id: "c", resource: "r", scope: "s" }, approved_by: { user_id: 1 })
      old_access, old_refresh = before_switch.issue_tokens(access("switching"), refresh("switching"))
      old_refresh = symbolize(storage.read_token(old_refresh))

      expect(symbolize(storage.read_token(old_access))).to include(kind: "access", grant_id: "switching")
      expect(storage.consume_refresh_token(old_refresh)).to be(true)
      expect(storage.consume_refresh_token(old_refresh)).to be(false)
      expect { storage.issue_token(access("switching")) }.to change { OAuthRecipes::TokenRows::McpToken.count }.by(1)
    end

    it "revokes the grant when revoking an encrypted token, since the token has no row" do
      storage.create_grant(code_id: "old", authorization_request: { client_id: "c", resource: "r", scope: "s" }, approved_by: { user_id: 1 })

      storage.revoke_token(symbolize(storage.read_token(before_switch.issue_token(access("old")))))

      expect(storage.find_grant("old")).to be_nil
    end
  end

  it "appear word for word in the docs" do
    docs = %w[oauth-storage.md oauth-storage-moving.md].map { |file| File.read(File.join(__dir__, "../../docs", file)) }.join

    Dir[File.join(OAuthRecipes::DIR, "*", "*.rb")].each do |file|
      expect(docs).to include(File.read(file)), "the docs don't quote #{file} exactly"
    end
  end
end
