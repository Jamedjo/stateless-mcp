RSpec.describe StatelessMcp::Result do
  it "names a result's type" do
    expect(described_class.complete({ tools: [] })).to eq(tools: [], resultType: "complete")
  end

  it "adds cache hints, scoped to the caller and stale at once, to a cacheable result" do
    expect(described_class.complete({ tools: [] }, cacheable: true)).to include(ttlMs: 0, cacheScope: "private")
  end

  it "answers server/discover with the server's own details" do
    server = StatelessMcp::Server.new(name: "notes", version: "2.0.0", instructions: "Read-only notes.")

    result = described_class.discover(server, capabilities: { tools: {} })

    expect(result).to include(supportedVersions: ["2026-07-28"], capabilities: { tools: {} }, instructions: "Read-only notes.", resultType: "complete")
    expect(result[:_meta]).to eq("io.modelcontextprotocol/serverInfo" => { name: "notes", version: "2.0.0" })
  end

  it "leaves out instructions a server doesn't give" do
    expect(described_class.discover(StatelessMcp::Server.new, capabilities: {})).not_to have_key(:instructions)
  end

  it "answers a tool call with its payload once, as JSON text, leaving out nil values" do
    result = described_class.tool(notes: [{ title: "Plan" }], next_cursor: nil)

    expect(result).to eq(content: [{ type: "text", text: '{"notes":[{"title":"Plan"}]}' }], isError: false, resultType: "complete")
  end

  it "refuses a tool call with a message for the model" do
    expect(described_class.refusal("No note 9")).to eq(content: [{ type: "text", text: "No note 9" }], isError: true, resultType: "complete")
  end
end
