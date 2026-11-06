RSpec.describe StatelessMcp::OAuth::ProtectedResource do
  # Tokens are their own names, and grants are looked up by id.
  let(:storage_class) do
    Class.new(StatelessMcp::OAuth::Storage) do
      attr_reader :tokens, :grants

      def initialize
        @tokens = {}
        @grants = {}
      end

      def read_token(token)
        tokens[token]
      end

      def find_grant(id)
        grants[id]
      end
    end
  end
  let(:storage) { storage_class.new }
  let(:grant) { Struct.new(:id, :client_id, :resource, :scope, :user_id).new("g1", "https://client.example/metadata.json", "https://notes.example/mcp", "notes:read", 42) }
  let(:protected_resource) { described_class.new(resource: "https://notes.example/mcp", authorization_server: "https://notes.example", storage: storage, scopes: ["notes:read"]) }

  before do
    storage.grants["g1"] = grant
    storage.tokens["good"] = { kind: "access", id: "t1", grant_id: "g1", expires_at: Time.now.to_i + 3600 }
  end

  def env(authorization = nil)
    Rack::MockRequest.env_for("/mcp", authorization ? { "HTTP_AUTHORIZATION" => authorization } : {})
  end

  describe "#verified_grant" do
    it "returns the grant behind a valid access token" do
      expect(protected_resource.verified_grant(env("Bearer good"))).to be(grant)
      expect(protected_resource.verified_grant(Rack::Request.new(env("bearer  good")))).to be(grant)
    end

    it "returns nil without a bearer token" do
      ["", "Basic good", "Bearer", "Bearer two words", "Bearer #{"a" * 5000}"].each do |header|
        expect(protected_resource.verified_grant(env(header))).to be_nil
      end
      expect(protected_resource.verified_grant(env)).to be_nil
    end

    it "returns nil for a token the storage doesn't know" do
      expect(protected_resource.verified_grant(env("Bearer unknown"))).to be_nil
    end

    it "returns nil for an expired token" do
      storage.tokens["expired"] = storage.tokens["good"].merge(expires_at: Time.now.to_i - 1)

      expect(protected_resource.verified_grant(env("Bearer expired"))).to be_nil
    end

    it "returns nil for a refresh token or an authorization code" do
      storage.tokens["refresh"] = storage.tokens["good"].merge(kind: "refresh")
      storage.tokens["code"] = storage.tokens["good"].except(:grant_id).merge(kind: "code", authorization_request: { client_id: "https://client.example/metadata.json", redirect_uri: "https://client.example/callback", code_challenge: "abc", scope: "notes:read", resource: "https://notes.example/mcp" }, approved_by: { user_id: 42 })

      expect(protected_resource.verified_grant(env("Bearer refresh"))).to be_nil
      expect(protected_resource.verified_grant(env("Bearer code"))).to be_nil
    end

    it "returns nil once the grant is revoked" do
      storage.grants.delete("g1")

      expect(protected_resource.verified_grant(env("Bearer good"))).to be_nil
    end

    it "returns nil for a grant to another MCP server" do
      storage.grants["g1"] = grant.dup.tap { |other| other.resource = "https://notes.example/admin/mcp" }

      expect(protected_resource.verified_grant(env("Bearer good"))).to be_nil
    end

    it "returns nil for claims the storage returns broken" do
      storage.tokens["broken"] = { kind: "access", id: "t1" }

      expect(protected_resource.verified_grant(env("Bearer broken"))).to be_nil
    end
  end

  describe "#verified_grant!" do
    def reason(authorization)
      protected_resource.verified_grant!(env(authorization))
    rescue StatelessMcp::OAuth::InvalidToken => error
      error.reason
    end

    it "returns the grant behind a valid access token" do
      expect(protected_resource.verified_grant!(env("Bearer good"))).to be(grant)
    end

    it "says why it refused a token, for the app's logs" do
      storage.tokens["expired"] = storage.tokens["good"].merge(expires_at: Time.now.to_i - 1)
      storage.tokens["refresh"] = storage.tokens["good"].merge(kind: "refresh")
      storage.tokens["revoked"] = storage.tokens["good"].merge(grant_id: "gone")
      storage.tokens["broken"] = { kind: "access", id: "t1" }
      storage.tokens["elsewhere"] = storage.tokens["good"].merge(grant_id: "admin")
      storage.grants["admin"] = grant.dup.tap { |other| other.resource = "https://notes.example/admin/mcp" }

      expect({ nil => reason(nil), "Basic good" => reason("Basic good"), "Bearer unknown" => reason("Bearer unknown"), "Bearer broken" => reason("Bearer broken"), "Bearer refresh" => reason("Bearer refresh"), "Bearer expired" => reason("Bearer expired"), "Bearer revoked" => reason("Bearer revoked"), "Bearer elsewhere" => reason("Bearer elsewhere") }).to eq(
        nil => :missing, "Basic good" => :missing, "Bearer unknown" => :unknown, "Bearer broken" => :unknown, "Bearer refresh" => :not_an_access_token,
        "Bearer expired" => :expired, "Bearer revoked" => :revoked, "Bearer elsewhere" => :other_mcp_server
      )
    end
  end

  it "points a 401 at the metadata, saying when a token was refused" do
    expect(protected_resource.unauthorized_headers).to eq("www-authenticate" => 'Bearer resource_metadata="https://notes.example/.well-known/oauth-protected-resource/mcp"')
    expect(protected_resource.unauthorized_headers(invalid_token: true)["www-authenticate"]).to end_with(', error="invalid_token"')
  end

  it "serves the protected resource metadata at the path RFC 9728 gives" do
    status, headers, body = protected_resource.metadata_app.call("REQUEST_METHOD" => "GET")

    expect(protected_resource.metadata_path).to eq("/.well-known/oauth-protected-resource/mcp")
    expect([status, headers["content-type"], headers["access-control-allow-origin"]]).to eq([200, "application/json", "*"])
    expect(JSON.parse(body.join)).to eq("resource" => "https://notes.example/mcp", "authorization_servers" => ["https://notes.example"], "scopes_supported" => ["notes:read"], "bearer_methods_supported" => ["header"])
  end

  it "puts the metadata at the root for an MCP server at the root" do
    expect(described_class.new(resource: "https://mcp.example/", authorization_server: "https://mcp.example", storage: storage).metadata_path).to eq("/.well-known/oauth-protected-resource")
  end

  it "refuses URLs a client couldn't trust" do
    expect { described_class.new(resource: "http://notes.example/mcp", authorization_server: "https://notes.example", storage: storage) }.to raise_error(ArgumentError, /resource must be an https URL/)
    expect { described_class.new(resource: "https://notes.example/mcp?x=1", authorization_server: "https://notes.example", storage: storage) }.to raise_error(ArgumentError, /query or fragment/)
    expect { described_class.new(resource: "https://notes.example/mcp", authorization_server: "notes", storage: storage) }.to raise_error(ArgumentError, /authorization_server/)
    expect(described_class.new(resource: "http://localhost:3000/mcp", authorization_server: "http://localhost:3000", storage: storage).resource).to eq("http://localhost:3000/mcp")
  end
end
