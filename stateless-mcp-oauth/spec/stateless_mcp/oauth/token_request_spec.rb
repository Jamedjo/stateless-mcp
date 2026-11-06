require "rack/test"
require_relative "../../support/memory_storage"

RSpec.describe StatelessMcp::OAuth::TokenRequest do
  let(:client_id) { "https://claude.ai/oauth/mcp-oauth-client-metadata" }
  let(:redirect_uri) { "https://claude.ai/api/mcp/auth_callback" }
  let(:verifier) { SecureRandom.urlsafe_base64(48) }
  let(:storage) { MemoryStorage.new }
  let(:notes) { StatelessMcp::OAuth::ProtectedResource.new(resource: "https://notes.example/mcp", authorization_server: "https://notes.example", storage: storage, scopes: ["notes:read", "notes:write"]) }
  let(:transport) do
    document = JSON.generate(client_id: client_id, client_name: "Claude", redirect_uris: [redirect_uri])
    FakeTransport.new(cache_control: "no-store") { document }
  end
  let(:server) { StatelessMcp::OAuth::AuthorizationServer.new(issuer: "https://notes.example", protected_resources: [notes], client_metadata_transport: transport) }

  # An authorization code, approved by user 7 on the consent page.
  def code(scope: "notes:read")
    authorization = server.authorization_request("response_type" => "code", "client_id" => client_id, "redirect_uri" => redirect_uri, "code_challenge" => StatelessMcp::OAuth::Pkce.challenge_for(verifier), "code_challenge_method" => "S256", "scope" => scope, "resource" => "https://notes.example/mcp")
    URI.decode_www_form(URI(authorization.approve(user_id: 7)).query).to_h.fetch("code")
  end

  def exchange(overrides = {})
    params = { "grant_type" => "authorization_code", "code" => code, "code_verifier" => verifier, "redirect_uri" => redirect_uri, "client_id" => client_id }.merge(overrides).compact
    server.token_request(params).tokens
  end

  def refresh(refresh_token, overrides = {})
    server.token_request({ "grant_type" => "refresh_token", "refresh_token" => refresh_token, "client_id" => client_id }.merge(overrides).compact).tokens
  end

  def verified_grant(access_token)
    notes.verified_grant(Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer #{access_token}"))
  end

  def refused(code = "invalid_grant", message = //)
    raise_error(an_instance_of(StatelessMcp::OAuth::Error).and(having_attributes(code: code, message: a_string_matching(message))))
  end

  describe "exchanging an authorization code" do
    it "issues an access token the MCP server accepts, and a refresh token" do
      tokens = exchange

      expect(tokens).to include(token_type: "Bearer", expires_in: 3600, scope: "notes:read", access_token: be_a(String), refresh_token: be_a(String))
      expect(verified_grant(tokens[:access_token])).to have_attributes(user_id: 7, client_id: client_id, scope: "notes:read")
    end

    it "needs the PKCE verifier, client and redirect_uri of the authorization request" do
      expect { exchange("code_verifier" => SecureRandom.urlsafe_base64(48)) }.to refused("invalid_grant", /code_verifier/)
      expect { exchange("client_id" => "https://other.example/client.json") }.to refused("invalid_grant", /another client/)
      expect { exchange("redirect_uri" => "https://claude.ai/elsewhere") }.to refused("invalid_grant", /redirect_uri/)
    end

    it "revokes the grant when an authorization code is exchanged again, since it may have been stolen" do
      used = code
      first = exchange("code" => used)

      expect { exchange("code" => used) }.to refused("invalid_grant", /already been used/)
      expect(verified_grant(first[:access_token])).to be_nil
      expect { refresh(first[:refresh_token]) }.to refused("invalid_grant", /grant has been revoked/)
    end

    it "leaves an authorization code unused when a check fails, so a wrong code verifier can't use up someone else's authorization code" do
      unused = code
      expect { exchange("code" => unused, "code_verifier" => SecureRandom.urlsafe_base64(48)) }.to refused

      expect(exchange("code" => unused)).to include(:access_token)
    end

    it "refuses an expired, unknown or missing authorization code" do
      issued = code
      later = Time.now + 121
      allow(Time).to receive(:now).and_return(later)
      expect { exchange("code" => issued) }.to refused("invalid_grant", /expired/)
      allow(Time).to receive(:now).and_call_original

      expect { exchange("code" => "nonsense") }.to refused("invalid_grant", /isn't one this server issued/)
      expect { exchange("code" => nil) }.to refused("invalid_grant", /code is required/)
    end

    it "refuses an authorization code read by another MCP server's storage" do
      admin = StatelessMcp::OAuth::ProtectedResource.new(resource: "https://notes.example/admin/mcp", authorization_server: "https://notes.example", storage: MemoryStorage.new)
      server = StatelessMcp::OAuth::AuthorizationServer.new(issuer: "https://notes.example", protected_resources: [notes, admin], client_metadata_transport: transport)
      request = { client_id: client_id, redirect_uri: redirect_uri, code_challenge: StatelessMcp::OAuth::Pkce.challenge_for(verifier), scope: "", resource: admin.resource }
      code = storage.issue_token(StatelessMcp::OAuth::Claims.new(kind: :code, id: SecureRandom.uuid, expires_at: Time.now.to_i + 60, authorization_request: request, approved_by: { user_id: 7 }).to_h)
      params = { "grant_type" => "authorization_code", "code" => code, "code_verifier" => verifier, "redirect_uri" => redirect_uri, "client_id" => client_id }

      expect { server.token_request(params).tokens }.to refused("invalid_grant", /wasn't issued for the MCP server it names/)
    end

    it "refuses a resource other than the authorization code's" do
      expect { exchange("resource" => "https://other.example/mcp") }.to refused("invalid_target")
      expect(exchange("resource" => "https://notes.example/mcp")).to include(:access_token)
    end
  end

  describe "refreshing" do
    it "issues new tokens and uses the refresh token up" do
      first = exchange
      second = refresh(first[:refresh_token])

      expect(verified_grant(second[:access_token])).to have_attributes(user_id: 7)
      expect(refresh(second[:refresh_token])).to include(:access_token)
    end

    it "revokes the grant when a used refresh token is sent again" do
      first = exchange
      second = refresh(first[:refresh_token])

      expect { refresh(first[:refresh_token]) }.to refused("invalid_grant", /already been used/)
      expect(verified_grant(second[:access_token])).to be_nil
      expect { refresh(second[:refresh_token]) }.to refused("invalid_grant", /grant has been revoked/)
    end

    it "refuses another client, a changed scope or a revoked grant" do
      tokens = exchange

      expect { refresh(tokens[:refresh_token], "client_id" => "https://other.example/client.json") }.to refused("invalid_grant", /another client/)
      expect { refresh(tokens[:refresh_token], "scope" => "notes:read notes:write") }.to refused("invalid_scope")
      expect(refresh(tokens[:refresh_token], "scope" => "notes:read")).to include(:access_token)
    end

    it "refuses an access token, an authorization code or an expired refresh token" do
      tokens = exchange

      expect { refresh(tokens[:access_token]) }.to refused("invalid_grant", /isn't one this server issued/)
      expect { refresh(code) }.to refused("invalid_grant", /isn't one this server issued/)
      allow(Time).to receive(:now).and_return(Time.now + 31 * 86_400)
      expect { refresh(tokens[:refresh_token]) }.to refused("invalid_grant", /expired/)
    end
  end

  it "refuses a client that sends a secret, an unknown grant type, or no client_id" do
    expect { server.token_request({ "grant_type" => "authorization_code", "client_id" => client_id, "client_secret" => "s" }) }.to raise_error(an_instance_of(StatelessMcp::OAuth::Error).and(having_attributes(code: "invalid_client", status: 401)))
    expect { server.token_request({ "grant_type" => "authorization_code", "client_id" => client_id }, authorization: "Basic abc") }.to refused("invalid_client")
    expect { server.token_request({ "grant_type" => "password", "client_id" => client_id }) }.to refused("unsupported_grant_type")
    expect { server.token_request({ "grant_type" => "authorization_code" }) }.to refused("invalid_request")
  end
end

RSpec.describe StatelessMcp::OAuth::TokenEndpoint do
  include Rack::Test::Methods

  let(:notes) { StatelessMcp::OAuth::ProtectedResource.new(resource: "https://notes.example/mcp", authorization_server: "https://notes.example", storage: MemoryStorage.new) }
  let(:transport) { FakeTransport.new { {} } }
  let(:server) { StatelessMcp::OAuth::AuthorizationServer.new(issuer: "https://notes.example", protected_resources: [notes], client_metadata_transport: transport) }

  def app
    Rack::Lint.new(server.token_app)
  end

  it "returns the OAuth error as JSON, with no-store, for a refused request" do
    post "/oauth/token", grant_type: "authorization_code", client_id: "https://claude.ai/client.json", code: "nonsense"

    expect(last_response.status).to eq(400)
    expect(JSON.parse(last_response.body)).to eq("error" => "invalid_grant", "error_description" => "The authorization code isn't one this server issued")
    expect(last_response.headers["cache-control"]).to eq("no-store")
  end

  it "returns a 401 naming the authentication scheme to a client that sends a secret" do
    post "/oauth/token", grant_type: "authorization_code", client_id: "https://claude.ai/client.json", client_secret: "s"

    expect(last_response.status).to eq(401)
    expect(last_response.headers["www-authenticate"]).to eq('Basic realm="https://notes.example"')

    post "/oauth/token", { grant_type: "authorization_code", client_id: "https://claude.ai/client.json" }, "HTTP_AUTHORIZATION" => "Bearer abc"
    expect([last_response.status, last_response.headers["www-authenticate"]]).to eq([401, 'Bearer realm="https://notes.example"'])
  end

  it "sends no WWW-Authenticate header with a 400" do
    post "/oauth/token", grant_type: "authorization_code", client_id: "https://claude.ai/client.json", code: "nonsense"

    expect(last_response.headers).not_to have_key("www-authenticate")
  end

  it "only accepts POST" do
    get "/oauth/token"

    expect(last_response.status).to eq(405)
  end
end
