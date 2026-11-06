RSpec.describe StatelessMcp::OAuth::AuthorizationRequest do
  let(:client_id) { "https://claude.ai/oauth/mcp-oauth-client-metadata" }
  let(:redirect_uri) { "https://claude.ai/api/mcp/auth_callback" }
  let(:verifier) { SecureRandom.urlsafe_base64(48) }
  # claude.ai's client metadata document, as claude.ai serves it.
  let(:documents) { { client_id => { client_id: client_id, client_name: "Claude", client_uri: "https://claude.ai", redirect_uris: [redirect_uri], grant_types: ["authorization_code", "refresh_token", "urn:ietf:params:oauth:grant-type:jwt-bearer"], response_types: ["code"], token_endpoint_auth_method: "none" } } }
  let(:transport) do
    documents = self.documents
    FakeTransport.new(cache_control: "no-store") { |url| documents[url] }
  end
  let(:fetched) { transport.fetched }
  # Keeps each issued token's claims, keyed by the token.
  let(:storage) do
    Class.new(StatelessMcp::OAuth::Storage) do
      def tokens
        @tokens ||= {}
      end

      def issue_token(claims)
        SecureRandom.hex(8).tap { |token| tokens[token] = claims }
      end
    end.new
  end
  let(:scopes) { ["notes:read"] }
  let(:notes) { StatelessMcp::OAuth::ProtectedResource.new(resource: "https://notes.example/mcp", authorization_server: "https://notes.example", storage: storage, scopes: scopes) }
  let(:protected_resources) { [notes] }
  let(:server) { StatelessMcp::OAuth::AuthorizationServer.new(issuer: "https://notes.example", protected_resources: protected_resources, client_metadata_transport: transport) }

  def params(overrides = {})
    { "response_type" => "code", "client_id" => client_id, "redirect_uri" => redirect_uri, "code_challenge" => StatelessMcp::OAuth::Pkce.challenge_for(verifier), "code_challenge_method" => "S256", "state" => "af0ifjsldkj", "scope" => "notes:read", "resource" => "https://notes.example/mcp" }.merge(overrides).compact
  end

  def authorization(overrides = {})
    server.authorization_request(params(overrides))
  end

  def query(url)
    URI.decode_www_form(URI(url).query).to_h
  end

  def untrusted(overrides = {})
    authorization(overrides)
  rescue StatelessMcp::OAuth::Error => error
    raise "expected a problem to show the person, got one to redirect" if error.redirectable?
    error
  end

  it "reads the client's name from its metadata document, and the redirect host" do
    request = authorization

    expect(request.problem).to be_nil
    expect(request.client).to have_attributes(name: "Claude", host: "claude.ai")
    expect(request.loopback_redirect?).to be(false)
    expect(request.redirect_host).to eq("claude.ai")
    expect(request.scopes).to eq(["notes:read"])
    expect(request.protected_resource).to be(notes)
  end

  it "stores nothing until approved" do
    authorization

    expect(storage.tokens).to be_empty
  end

  describe "approving" do
    it "sends an authorization code to the redirect_uri, with state and iss" do
      url = authorization.approve(user_id: 7)

      expect(url).to start_with("#{redirect_uri}?")
      expect(query(url)).to include("state" => "af0ifjsldkj", "iss" => "https://notes.example", "code" => be_a(String))
    end

    it "issues the authorization code through the MCP server's storage, with what was approved" do
      code = query(authorization.approve(user_id: 7))["code"]
      claims = StatelessMcp::OAuth::Claims.from_h(storage.tokens.fetch(code))

      expect(claims.kind).to eq(:code)
      expect(claims.grant_id).to be_nil
      expect(claims.expires_at).to be_within(2).of(Time.now.to_i + 120)
      expect(claims.authorization_request).to eq(client_id: client_id, redirect_uri: redirect_uri, code_challenge: StatelessMcp::OAuth::Pkce.challenge_for(verifier), scope: "notes:read", resource: "https://notes.example/mcp")
      expect(claims.approved_by).to eq(user_id: 7)
    end

    it "keeps the redirect_uri's own query" do
      documents[client_id][:redirect_uris] = ["https://claude.ai/cb?tenant=1"]

      expect(query(authorization("redirect_uri" => "https://claude.ai/cb?tenant=1").approve(user_id: 7))).to include("tenant" => "1", "code" => be_a(String))
    end

    it "refuses to approve a request with a problem" do
      expect { authorization("code_challenge_method" => "plain").approve(user_id: 7) }.to raise_error(ArgumentError, /Can't approve.*code_challenge_method/)
    end
  end

  it "sends access_denied back on denial, with state and iss" do
    expect(query(authorization.deny)).to eq("error" => "access_denied", "state" => "af0ifjsldkj", "iss" => "https://notes.example")
  end

  describe "errors sent to the client" do
    def problem(overrides)
      authorization(overrides).problem
    end

    it "includes anything but the code flow with S256 PKCE" do
      expect(problem("response_type" => "token")&.code).to eq("unsupported_response_type")
      expect(problem("code_challenge_method" => "plain")&.code).to eq("invalid_request")
      expect(problem("code_challenge_method" => nil, "code_challenge" => nil)&.code).to eq("invalid_request")
      expect(problem("code_challenge" => "short")&.code).to eq("invalid_request")
    end

    it "includes an unknown resource, but accepts a missing one or one with an upper-case scheme and host" do
      expect(problem("resource" => "https://other.example/mcp")&.code).to eq("invalid_target")
      expect(problem("resource" => nil)).to be_nil
      expect(problem("resource" => "HTTPS://NOTES.EXAMPLE/mcp")).to be_nil
    end

    context "with two MCP servers" do
      let(:admin) { StatelessMcp::OAuth::ProtectedResource.new(resource: "https://notes.example/admin/mcp", authorization_server: "https://notes.example", storage: storage, scopes: ["admin"]) }
      let(:protected_resources) { [notes, admin] }

      it "needs the resource, and offers that server's scopes" do
        expect(problem("resource" => nil)&.code).to eq("invalid_target")
        expect(authorization("resource" => "https://notes.example/admin/mcp", "scope" => "admin").scopes).to eq(["admin"])
      end
    end

    it "drops scopes the MCP server doesn't offer, and refuses when none are left" do
      expect(authorization("scope" => "notes:read offline_access").scopes).to eq(["notes:read"])
      expect(problem("scope" => "notes:write")&.code).to eq("invalid_scope")
    end

    context "when the client asks for no scope" do
      let(:scopes) { ["notes:read", "notes:write"] }

      it "refuses, when the MCP server has no default scopes" do
        expect(problem("scope" => nil)&.code).to eq("invalid_scope")
      end

      it "gives only the default scopes, not every scope" do
        notes = StatelessMcp::OAuth::ProtectedResource.new(resource: "https://notes.example/mcp", authorization_server: "https://notes.example", storage: storage, scopes: scopes, default_scopes: ["notes:read"])
        server = StatelessMcp::OAuth::AuthorizationServer.new(issuer: "https://notes.example", protected_resources: [notes], client_metadata_transport: transport)

        expect(server.authorization_request(params("scope" => nil)).scopes).to eq(["notes:read"])
      end
    end

    context "on an MCP server without scopes" do
      let(:scopes) { [] }

      it "accepts any scope parameter" do
        expect(problem("scope" => "anything")).to be_nil
      end
    end

    it "goes back with state and iss, and the error" do
      url = authorization("response_type" => "token").error_redirect_url

      expect(query(url)).to include("error" => "unsupported_response_type", "state" => "af0ifjsldkj", "iss" => "https://notes.example")
    end

    it "includes a state too long to send back" do
      expect(problem("state" => "a" * 1025)&.message).to eq("state is too long")
    end
  end

  describe "errors shown to the person instead" do
    it "includes a redirect_uri the document doesn't list" do
      expect(untrusted("redirect_uri" => "https://attacker.example/callback").message).to eq("redirect_uri isn't one claude.ai listed")
      expect(untrusted("redirect_uri" => nil).code).to eq("invalid_request")
    end

    it "includes a client_id that isn't an https URL, without fetching it" do
      expect(untrusted("client_id" => "http://claude.ai/oauth/mcp-oauth-client-metadata").code).to eq("invalid_client")
      expect(untrusted("client_id" => nil).code).to eq("invalid_client")
      expect(fetched).to be_empty
    end

    it "includes a client whose document can't be loaded or fails the checks" do
      expect(untrusted("client_id" => "https://claude.ai/missing").message).to eq("Couldn't load the client's metadata document from claude.ai")

      documents[client_id][:client_id] = "https://claude.ai/other"
      expect(untrusted.message).to eq("The client metadata document names a different client_id")
    end

    it "includes parameters sent as anything but strings" do
      expect(untrusted("redirect_uri" => [redirect_uri]).code).to eq("invalid_request")
    end
  end

  it "accepts any port of a loopback redirect, and says when the person would go back to loopback" do
    documents[client_id][:redirect_uris] = ["https://claude.ai/api/mcp/auth_callback", "http://127.0.0.1:3000/callback"]

    request = authorization("redirect_uri" => "http://127.0.0.1:54321/callback")

    expect(request.problem).to be_nil
    expect(request.loopback_redirect?).to be(true)
    expect(request.redirect_host).to eq("127.0.0.1")
  end
end
