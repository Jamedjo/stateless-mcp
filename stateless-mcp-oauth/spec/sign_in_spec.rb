require "active_record"
require "active_support/message_encryptor"
require "rack/test"
require "tmpdir"
require_relative "support/oauth_recipes"

# A sign-in from the consent page to a refreshed access token, run against each
# storage example in docs/oauth-storage.md.
RSpec.describe "A sign-in, end to end" do
  include Rack::Test::Methods

  before(:all) do
    @dir = Dir.mktmpdir
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: File.join(@dir, "sign_in.sqlite3"), pool: 10, timeout: 5000)
    OAuthRecipes.migrate(OAuthRecipes::Encrypted::CreateMcpGrants, OAuthRecipes::Encrypted::AddRefreshTokenIdToMcpGrants, OAuthRecipes::TokenRows::CreateMcpTokens)
  end

  after(:all) do
    ActiveRecord::Base.remove_connection
    FileUtils.remove_entry(@dir)
  end

  let(:client_id) { "https://claude.ai/oauth/mcp-oauth-client-metadata" }
  let(:redirect_uri) { "https://claude.ai/api/mcp/auth_callback" }
  let(:verifier) { SecureRandom.urlsafe_base64(48) }
  let(:transport) do
    document = JSON.generate(client_id: client_id, client_name: "Claude", redirect_uris: [redirect_uri])
    FakeTransport.new(cache_control: "no-store") { document }
  end
  let(:notes) { StatelessMcp::OAuth::ProtectedResource.new(resource: "https://notes.example/mcp", authorization_server: "https://notes.example", storage: storage, scopes: ["notes:read"]) }
  let(:server) { StatelessMcp::OAuth::AuthorizationServer.new(issuer: "https://notes.example", protected_resources: [notes], client_metadata_transport: transport) }

  def app
    server.token_app
  end

  def token_response(params)
    post "/oauth/token", params.merge(client_id: client_id)
    [last_response.status, JSON.parse(last_response.body)]
  end

  def verified_grant(access_token)
    notes.verified_grant(Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer #{access_token}"))
  end

  shared_examples "a sign-in" do
    it "approves the client, accepts its access tokens, refreshes them, and revokes the grant when a refresh token is reused" do
      authorization = server.authorization_request("response_type" => "code", "client_id" => client_id, "redirect_uri" => redirect_uri, "code_challenge" => StatelessMcp::OAuth::Pkce.challenge_for(verifier), "code_challenge_method" => "S256", "scope" => "notes:read", "resource" => "https://notes.example/mcp")
      code = URI.decode_www_form(URI(authorization.approve(user_id: 42)).query).to_h.fetch("code")

      status, first = token_response(grant_type: "authorization_code", code: code, code_verifier: verifier, redirect_uri: redirect_uri)
      expect(status).to eq(200)
      expect(verified_grant(first["access_token"])).to have_attributes(user_id: 42, client_id: client_id)

      status, second = token_response(grant_type: "refresh_token", refresh_token: first["refresh_token"])
      expect(status).to eq(200)
      expect(verified_grant(second["access_token"])).to have_attributes(user_id: 42)

      status, error = token_response(grant_type: "refresh_token", refresh_token: first["refresh_token"])
      expect([status, error["error"]]).to eq([400, "invalid_grant"])
      expect(verified_grant(second["access_token"])).to be_nil

      status, = token_response(grant_type: "authorization_code", code: code, code_verifier: verifier, redirect_uri: redirect_uri)
      expect(status).to eq(400)
    end
  end

  describe "with encrypted tokens" do
    let(:storage) { OAuthRecipes::Encrypted::McpOAuthStorage.new }

    it_behaves_like "a sign-in"
  end

  describe "with token rows" do
    let(:storage) { OAuthRecipes::TokenRows::McpOAuthStorage.new }

    it_behaves_like "a sign-in"
  end
end
