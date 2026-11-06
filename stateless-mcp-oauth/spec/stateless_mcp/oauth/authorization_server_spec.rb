RSpec.describe StatelessMcp::OAuth::AuthorizationServer do
  let(:transport) { FakeTransport.new { {} } }
  let(:notes) { StatelessMcp::OAuth::ProtectedResource.new(resource: "https://notes.example/mcp", authorization_server: "https://notes.example", storage: StatelessMcp::OAuth::Storage.new, scopes: ["notes:read"]) }
  let(:admin) { StatelessMcp::OAuth::ProtectedResource.new(resource: "https://notes.example/admin/mcp", authorization_server: "https://notes.example", storage: StatelessMcp::OAuth::Storage.new, scopes: ["notes:read", "admin"]) }
  let(:server) { described_class.new(issuer: "https://notes.example", protected_resources: [notes, admin], client_metadata_transport: transport) }

  it "serves RFC 8414 metadata that supports client ID metadata documents" do
    expect(server.metadata).to eq(
      issuer: "https://notes.example",
      authorization_endpoint: "https://notes.example/oauth/authorize",
      token_endpoint: "https://notes.example/oauth/token",
      response_types_supported: ["code"],
      response_modes_supported: ["query"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none"],
      scopes_supported: ["notes:read", "admin"],
      client_id_metadata_document_supported: true,
      authorization_response_iss_parameter_supported: true
    )
  end

  it "serves the metadata at the well-known path" do
    status, headers, body = server.metadata_app.call("REQUEST_METHOD" => "GET")

    expect(server.metadata_path).to eq("/.well-known/oauth-authorization-server")
    expect([status, headers["content-type"]]).to eq([200, "application/json"])
    expect(JSON.parse(body.join)["issuer"]).to eq("https://notes.example")
  end

  it "finds the protected resource a client names" do
    expect(server.protected_resource("https://notes.example/admin/mcp")).to be(admin)
    expect(server.protected_resource("https://elsewhere.example/mcp")).to be_nil
  end

  it "accepts custom endpoint paths" do
    custom = described_class.new(issuer: "https://notes.example", protected_resources: [notes], authorization_path: "/mcp/authorize", token_path: "/mcp/token", client_metadata_transport: transport)

    expect([custom.authorization_endpoint, custom.token_endpoint]).to eq(["https://notes.example/mcp/authorize", "https://notes.example/mcp/token"])
  end

  it "refuses an issuer that isn't an https origin, and protected resources with a different authorization server" do
    ["http://notes.example", "https://notes.example/oauth", "https://notes.example?x=1", "notes"].each do |issuer|
      expect { described_class.new(issuer: issuer, protected_resources: [notes], client_metadata_transport: transport) }.to raise_error(ArgumentError, /issuer must be an https origin/), issuer
    end
    expect { described_class.new(issuer: "https://elsewhere.example", protected_resources: [notes], client_metadata_transport: transport) }.to raise_error(ArgumentError, %r{names https://notes.example as its authorization server})
    expect { described_class.new(issuer: "https://notes.example", protected_resources: [], client_metadata_transport: transport) }.to raise_error(ArgumentError, /at least one/)
  end

  it "refuses an endpoint path that doesn't start with /" do
    expect { described_class.new(issuer: "https://notes.example", protected_resources: [notes], token_path: "oauth/token", client_metadata_transport: transport) }.to raise_error(ArgumentError, /token_path must be a path/)
  end

  it "accepts localhost redirects unless localhost_redirects is false" do
    claude_code = JSON.generate(client_id: "https://claude.ai/oauth/claude-code-client-metadata", client_name: "Claude Code", redirect_uris: ["http://localhost/callback", "http://127.0.0.1/callback"], token_endpoint_auth_method: "none")
    document = FakeTransport.new { claude_code }

    expect(described_class.new(issuer: "https://notes.example", protected_resources: [notes], client_metadata_transport: document).client("https://claude.ai/oauth/claude-code-client-metadata").redirect_uri?("http://localhost:5555/callback")).to be(true)
    strict = described_class.new(issuer: "https://notes.example", protected_resources: [notes], client_metadata_transport: document, localhost_redirects: false)
    expect { strict.client("https://claude.ai/oauth/claude-code-client-metadata") }.to raise_error(StatelessMcp::OAuth::Error, /redirect_uris/)
  end

  it "fetches client metadata documents with ssrf_filter by default" do
    expect(described_class.new(issuer: "https://notes.example", protected_resources: [notes]).client_metadata_transport).to be_a(StatelessMcp::OAuth::DocumentTransport)
  end
end
