RSpec.describe "Calling MCP tools", type: :request do
  let!(:plan) { Note.create!(title: "Plan", body: "Ship the first version.", tags: ["work"], created_at: Time.utc(2026, 10, 3)) }
  let!(:groceries) { Note.create!(title: "Groceries", body: "Eggs", tags: ["home"], created_at: Time.utc(2026, 10, 2)) }
  let!(:ideas) { Note.create!(title: "Ideas", tags: ["work"], created_at: Time.utc(2026, 10, 1)) }

  after { Note.delete_all }

  def call_tool(name, path: "/mcp", headers: {}, **arguments)
    call_mcp("tools/call", { name: name, arguments: arguments }, path: path, headers: headers).fetch("result")
  end

  def tool_payload(name, **arguments)
    JSON.parse(call_tool(name, **arguments)["content"].first["text"])
  end

  def titles(payload)
    payload["notes"].map { |note| note["title"] }
  end

  it "answers with the result once, as JSON text for the model" do
    result = call_tool("get_note", note_id: plan.id)

    expect(result).to include("isError" => false, "resultType" => "complete")
    expect(result).not_to have_key("structuredContent")
    expect(JSON.parse(result["content"].first["text"])).to eq("id" => plan.id, "title" => "Plan", "tags" => ["work"], "created_at" => "2026-10-03T00:00:00Z")
  end

  it "reads arguments through tool_params" do
    expect(titles(tool_payload("list_notes", tag: "work"))).to eq(["Plan", "Ideas"])
  end

  it "routes a tool named in a base64-wrapped Mcp-Name" do
    result = call_tool("get_note", note_id: plan.id, headers: { "HTTP_MCP_NAME" => "=?base64?#{["get_note"].pack("m0")}?=" })

    expect(result["isError"]).to be(false)
  end

  describe "paging" do
    it "pages a list with next_cursor, by the server's page size" do
      first_page = tool_payload("list_notes")
      second_page = tool_payload("list_notes", cursor: first_page["next_cursor"])

      expect(titles(first_page) + titles(second_page)).to eq(["Plan", "Groceries", "Ideas"])
      expect(second_page).not_to have_key("next_cursor")
    end

    it "takes the limit a call asks for" do
      expect(titles(tool_payload("list_notes", limit: 3))).to eq(["Plan", "Groceries", "Ideas"])
    end

    it "returns a long text in parts" do
      first_part = tool_payload("get_note_body", note_id: plan.id)
      second_part = tool_payload("get_note_body", note_id: plan.id, cursor: first_part["next_cursor"])
      third_part = tool_payload("get_note_body", note_id: plan.id, cursor: second_part["next_cursor"])

      expect([first_part, second_part, third_part].map { |part| part["body"] }.join).to eq("Ship the first version.")
      expect(third_part).not_to have_key("next_cursor")
    end

    it "pages each server by its own page size" do
      admin_page = JSON.parse(call_tool("list_notes", path: "/admin/mcp")["content"].first["text"])

      expect(admin_page["notes"]).to eq(["Plan"])
      expect(titles(tool_payload("list_notes")).size).to eq(2)
    end
  end

  describe "refusals the model can act on" do
    it "refuses a call missing a required argument" do
      result = call_tool("get_note")

      expect(result["isError"]).to be(true)
      expect(result["content"].first["text"]).to eq("Missing required arguments: note_id")
    end

    it "refuses an argument of the wrong type" do
      result = call_tool("list_notes", limit: "lots")

      expect(result["isError"]).to be(true)
      expect(result["content"].first["text"]).to start_with("Invalid arguments")
    end

    it "refuses a limit past the server's largest page" do
      expect(call_tool("list_notes", limit: 101)["isError"]).to be(true)
    end

    it "refuses a cursor it didn't issue" do
      result = call_tool("list_notes", cursor: "page-2")

      expect(result["isError"]).to be(true)
      expect(result["content"].first["text"]).to eq("cursor must be a next_cursor from an earlier result")
    end

    it "explains a date it can't read" do
      result = call_tool("list_notes", created_after: "last tuesday-ish")

      expect(result["isError"]).to be(true)
      expect(result["content"].first["text"]).to include("ISO 8601")
    end

    it "reads a date it can" do
      expect(titles(tool_payload("list_notes", created_after: "2026-10-02"))).to eq(["Plan", "Groceries"])
    end

    it "answers StatelessMcp::InvalidArgument as a refusal" do
      result = call_tool("get_note", note_id: 99)

      expect(result["isError"]).to be(true)
      expect(result["content"].first["text"]).to eq("No note 99")
    end
  end

  it "answers arguments that aren't an object as a malformed call" do
    call_mcp("tools/call", { name: "get_note", arguments: "plan" })

    expect(last_response.status).to eq(400)
    expect(json_response["error"]).to eq("code" => -32602, "message" => "arguments must be an object")
  end

  it "answers a tool's own failure as an internal error, reporting the cause only to the app" do
    allow(Note).to receive(:all).and_raise("store on fire")
    expect(Rails.error).to receive(:report).with(an_instance_of(RuntimeError).and(having_attributes(message: "store on fire")), source: "stateless_mcp")

    call_mcp("tools/call", { name: "list_notes", arguments: {} })

    expect(json_response["error"]).to eq("code" => -32603, "message" => "Internal error")
    expect(last_response.status).to eq(200)
  end

  it "leaves the app's rate limit its own 429" do
    3.times { post_mcp "/mcp", "tools/call", { name: "get_note", arguments: { note_id: plan.id } }, headers: { "HTTP_X_CALLER" => "rate-limit-spec" } }

    expect(last_response.status).to eq(429)
  end
end
