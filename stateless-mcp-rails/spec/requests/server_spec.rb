RSpec.describe "An MCP server's own methods", type: :request do
  def tools(path: "/mcp")
    call_mcp("tools/list", path: path).dig("result", "tools")
  end

  describe "server/discover" do
    it "describes the server from config" do
      result = call_mcp("server/discover").fetch("result")

      expect(result).to include("supportedVersions" => ["2026-07-28"], "capabilities" => { "tools" => {} }, "instructions" => "Notes kept in memory, newest first.", "resultType" => "complete", "ttlMs" => 0, "cacheScope" => "private")
      expect(result.dig("_meta", "io.modelcontextprotocol/serverInfo")).to eq("name" => "notes", "version" => "2.0.0")
    end
  end

  describe "tools/list" do
    it "lists the routed tools, in the order they're drawn" do
      expect(tools.map { |tool| tool["name"] }).to eq(["list_notes", "get_note", "get_note_body"])
    end

    it "describes each tool's arguments" do
      tool = tools.find { |entry| entry["name"] == "get_note_body" }

      expect(tool).to include("title" => "Get a note's text", "annotations" => include("readOnlyHint" => true))
      expect(tool["inputSchema"]).to include("type" => "object", "required" => ["note_id"], "properties" => include("note_id", "cursor"))
    end

    it "is cacheable for this caller only" do
      expect(call_mcp("tools/list")["result"]).to include("ttlMs" => 0, "cacheScope" => "private", "resultType" => "complete")
    end
  end

  it "answers a method it lacks with a 404, the handshake included" do
    expect(call_mcp("resources/list").fetch("error")).to include("code" => -32601, "message" => "Method not found")
    expect(last_response.status).to eq(404)

    expect(call_mcp("initialize").dig("error", "code")).to eq(-32601)
  end

  it "answers a call to a tool that isn't routed as a bad argument" do
    expect(call_mcp("tools/call", { name: "delete_everything", arguments: {} }).fetch("error")).to eq("code" => -32602, "message" => "Unknown tool: delete_everything")
    expect(last_response.status).to eq(400)
  end

  it "accepts a notification without answering it" do
    post "/mcp", JSON.generate(jsonrpc: "2.0", method: "notifications/initialized"), mcp_headers("notifications/initialized")

    expect(last_response.status).to eq(202)
    expect(last_response.body).to be_empty
  end

  it "answers GET and DELETE with 405" do
    get "/mcp"
    expect(last_response.status).to eq(405)

    delete "/mcp"
    expect(last_response.status).to eq(405)
  end

  it "refuses a body past the configured limit" do
    call_mcp("tools/list", { padding: "a" * 4096 })

    expect(last_response.status).to eq(400)
    expect(json_response.dig("error", "message")).to eq("Request body is larger than 4096 bytes")
  end

  it "runs the app's base controller first, as the server controller inherits from it" do
    post_mcp "/mcp", "tools/list", {}, headers: { "HTTP_X_REFUSE" => "yes" }

    expect(last_response.status).to eq(403)
  end

  it "refuses a request from another site's page before the app sees it" do
    post_mcp "/mcp", "tools/list", {}, headers: { "HTTP_ORIGIN" => "https://elsewhere.example" }

    expect(last_response.status).to eq(403)
    expect(json_response.dig("error", "message")).to eq("Origin not allowed")
  end

  describe "two servers in one app" do
    it "lists only each server's own tools" do
      expect(tools(path: "/admin/mcp").map { |tool| tool["name"] }).to eq(["list_notes", "count_notes"])
      expect(tools.map { |tool| tool["name"] }).not_to include("count_notes")
    end

    it "describes each server as itself" do
      expect(call_mcp("server/discover", path: "/admin/mcp").dig("result", "_meta", "io.modelcontextprotocol/serverInfo", "name")).to eq("admin")
    end

    it "describes paging with each server's own page sizes" do
      limit = ->(path) { tools(path: path).find { |tool| tool["name"] == "list_notes" }.dig("inputSchema", "properties", "limit") }

      expect(limit.call("/mcp")).to include("maximum" => 100, "description" => "How many notes to return, 2 by default")
      expect(limit.call("/admin/mcp")).to include("maximum" => 3, "description" => "How many notes to return, 1 by default")
    end

    it "holds each to its own body limit" do
      call_mcp("tools/list", { padding: "a" * 3000 })
      expect(last_response.status).to eq(200)

      call_mcp("tools/list", { padding: "a" * 3000 }, path: "/admin/mcp")
      expect(json_response.dig("error", "message")).to eq("Request body is larger than 2048 bytes")
    end

    it "doesn't route one server's tools on the other's path" do
      expect(call_mcp("tools/call", { name: "count_notes", arguments: {} }).dig("error", "message")).to eq("Unknown tool: count_notes")
    end
  end
end
