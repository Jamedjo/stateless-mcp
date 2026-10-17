RSpec.describe StatelessMcp::Middleware do
  include Rack::Test::Methods
  include McpRequests

  let(:server) { StatelessMcp::Server.new(path: "/mcp", name: "notes", max_body_bytes: 2048) }
  let(:seen) { {} }

  # Records what reached the app, and answers with its own body read.
  def app
    server = self.server
    seen = self.seen
    Rack::Builder.new do
      use StatelessMcp::Middleware, server: server
      run lambda { |env|
        seen.merge!(server: env[StatelessMcp::Server::ENV_KEY], request: env[StatelessMcp::REQUEST_ENV_KEY], mcp_name: env["HTTP_MCP_NAME"], input: env["rack.input"]&.read)
        [200, { "content-type" => "text/plain" }, ["app"]]
      }
    end
  end

  def error
    json_response.fetch("error")
  end

  it "passes a valid request to the app with its server and parsed body" do
    post_mcp "/mcp", "tools/list"

    expect(last_response.body).to eq("app")
    expect(seen[:server]).to be(server)
    expect(seen[:request]).to include("method" => "tools/list", "id" => 1)
  end

  it "leaves the body readable for the app" do
    post_mcp "/mcp", "tools/list"

    expect(JSON.parse(seen[:input])["method"]).to eq("tools/list")
  end

  it "leaves other paths alone" do
    post "/other", "not json"

    expect(last_response.body).to eq("app")
    expect(seen[:server]).to be_nil
  end

  it "requires a server" do
    expect { described_class.new(->(_env) { }, server: "/mcp") }.to raise_error(ArgumentError, /StatelessMcp::Server/)
  end

  it "answers GET and DELETE with 405, as a server without streams or sessions" do
    get "/mcp"
    expect(last_response.status).to eq(405)
    expect(last_response.headers["allow"]).to eq("POST")

    delete "/mcp"
    expect(last_response.status).to eq(405)
  end

  describe "the request body" do
    it "is refused past max_body_bytes" do
      post_mcp "/mcp", "tools/list", { padding: "a" * 2048 }

      expect(last_response.status).to eq(400)
      expect(error).to include("code" => -32600, "message" => "Request body is larger than 2048 bytes")
      expect(json_response["id"]).to be_nil
    end

    it "is refused without reading past the limit" do
      input = StringIO.new(JSON.generate(mcp_body("tools/list", { padding: "a" * 10_000 })))

      post "/mcp", {}, mcp_headers("tools/list").merge("rack.input" => input, "CONTENT_LENGTH" => nil)

      expect(last_response.status).to eq(400)
      expect(input.pos).to eq(2049)
    end

    it "is refused from its declared length alone, before any of it is read" do
      input = StringIO.new("{}")

      post "/mcp", {}, mcp_headers("tools/list").merge("rack.input" => input, "CONTENT_LENGTH" => "5000")

      expect(last_response.status).to eq(400)
      expect(input.pos).to eq(0)
    end

    it "is refused when it isn't JSON" do
      post "/mcp", "{", mcp_headers("tools/list")

      expect(last_response.status).to eq(400)
      expect(error).to include("code" => -32700, "message" => "Parse error")
    end

    it "is refused as a batch" do
      post "/mcp", JSON.generate([mcp_body("tools/list")]), mcp_headers("tools/list")

      expect(last_response.status).to eq(400)
      expect(error).to include("code" => -32600, "message" => "Body must be a single JSON-RPC request object")
    end
  end

  # 2026-07-28 requires the routing headers to agree with the body, so a proxy
  # routing on them can't be shown one method while the server runs another.
  describe "the headers" do
    it "are refused when Mcp-Method disagrees with the body" do
      post_mcp "/mcp", "tools/list", {}, headers: { "HTTP_MCP_METHOD" => "server/discover" }

      expect(last_response.status).to eq(400)
      expect(error).to include("code" => -32020, "message" => "Header mismatch: Mcp-Method header value 'server/discover' does not match body value 'tools/list'")
      expect(json_response["id"]).to eq(1)
    end

    it "are refused without Mcp-Method" do
      post_mcp "/mcp", "tools/list", {}, headers: { "HTTP_MCP_METHOD" => nil }

      expect(error).to include("code" => -32020, "message" => "Header mismatch: Mcp-Method header is required")
    end

    it "are refused when a tool call carries no Mcp-Name" do
      post_mcp "/mcp", "tools/call", { name: "list_notes", arguments: {} }, headers: { "HTTP_MCP_NAME" => nil }

      expect(last_response.status).to eq(400)
      expect(error["message"]).to eq("Header mismatch: Mcp-Name header is required")
    end

    it "are refused when Mcp-Name names a different tool than the body" do
      post_mcp "/mcp", "tools/call", { name: "get_note", arguments: {} }, headers: { "HTTP_MCP_NAME" => "list_notes" }

      expect(error["code"]).to eq(-32020)
    end

    it "decode a base64-wrapped Mcp-Name before comparing it, and hand the app the name itself" do
      name = "résumé_notes"

      post_mcp "/mcp", "tools/call", { name: name, arguments: {} }, headers: { "HTTP_MCP_NAME" => "=?base64?#{[name].pack("m0")}?=" }

      expect(last_response.body).to eq("app")
      expect(seen[:mcp_name]).to eq(name)
    end

    it "are refused without MCP-Protocol-Version" do
      post_mcp "/mcp", "tools/list", {}, headers: { "HTTP_MCP_PROTOCOL_VERSION" => nil }

      expect(last_response.status).to eq(400)
      expect(error).to include("code" => -32020, "message" => "Header mismatch: MCP-Protocol-Version header is required")
    end

    it "tell a client asking for an unsupported version which ones are supported" do
      post_mcp "/mcp", "tools/list", {}, headers: { "HTTP_MCP_PROTOCOL_VERSION" => "2099-01-01" }

      expect(last_response.status).to eq(400)
      expect(error).to include("code" => -32022, "data" => { "supported" => ["2026-07-28"], "requested" => "2099-01-01" })
    end

    it "are refused when MCP-Protocol-Version disagrees with the body's _meta" do
      body = mcp_body("tools/list")
      body[:params][:_meta]["io.modelcontextprotocol/protocolVersion"] = "2025-11-25"

      post "/mcp", JSON.generate(body), mcp_headers("tools/list")

      expect(error["code"]).to eq(-32020)
    end

    it "are refused without the _meta envelope" do
      post "/mcp", JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/list"), mcp_headers("tools/list")

      expect(last_response.status).to eq(400)
      expect(error["code"]).to eq(-32602)
    end

    it "let a notification through without an envelope" do
      post "/mcp", JSON.generate(jsonrpc: "2.0", method: "notifications/initialized"), mcp_headers("notifications/initialized")

      expect(last_response.body).to eq("app")
    end
  end

  describe "two servers in one app" do
    let(:admin) { StatelessMcp::Server.new(path: "/admin/mcp", name: "admin", max_body_bytes: 512) }

    def app
      server = self.server
      admin = self.admin
      seen = self.seen
      Rack::Builder.new do
        use StatelessMcp::Middleware, server: server
        use StatelessMcp::Middleware, server: admin
        run lambda { |env|
          seen[:server] = env[StatelessMcp::Server::ENV_KEY]
          [200, {}, ["app"]]
        }
      end
    end

    it "hands each request the server for its path" do
      post_mcp "/admin/mcp", "tools/list"
      expect(seen[:server]).to be(admin)

      post_mcp "/mcp", "tools/list"
      expect(seen[:server]).to be(server)
    end

    it "holds each to its own body limit" do
      post_mcp "/mcp", "tools/list", { padding: "a" * 1000 }
      expect(last_response.body).to eq("app")

      post_mcp "/admin/mcp", "tools/list", { padding: "a" * 1000 }
      expect(error["message"]).to eq("Request body is larger than 512 bytes")
    end
  end
end
