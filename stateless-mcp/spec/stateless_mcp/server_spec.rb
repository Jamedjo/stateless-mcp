RSpec.describe StatelessMcp::Server do
  it "has a default for every setting" do
    server = described_class.new

    expect(server).to have_attributes(path: "/mcp", name: "mcp", version: "1.0.0", title: nil, instructions: nil, max_body_bytes: 1_048_576, page_size: 20, max_page_size: 100)
    expect(server.tool_verbs).to include(index: "list", show: "get", destroy: "delete")
  end

  it "takes nil as the default, as unset Rails config arrives" do
    expect(described_class.new(path: nil, page_size: nil)).to have_attributes(path: "/mcp", page_size: 20)
  end

  it "is frozen, so threads can share it" do
    server = described_class.new(name: "notes")

    expect(server).to be_frozen
    expect(server.name).to be_frozen
    expect(server.tool_verbs).to be_frozen
  end

  it "describes itself as serverInfo, leaving out an unset title" do
    expect(described_class.new(name: "notes", version: "2.1.0").info).to eq(name: "notes", version: "2.1.0")
    expect(described_class.new(title: "Notes").info).to include(title: "Notes")
  end

  it "merges tool_verbs over the defaults" do
    verbs = described_class.new(tool_verbs: { "index" => "find" }).tool_verbs

    expect(verbs).to include(index: "find", show: "get")
  end

  it "serves only its own path" do
    server = described_class.new(path: "/admin/mcp")

    expect(server.endpoint?("PATH_INFO" => "/admin/mcp")).to be(true)
    expect(server.endpoint?("PATH_INFO" => "/mcp")).to be(false)
    expect(server.endpoint?("PATH_INFO" => "/admin/mcp/extra")).to be(false)
  end

  describe "validation" do
    def error_for(**settings)
      described_class.new(**settings)
    rescue described_class::Invalid => error
      error.message
    end

    it "refuses a setting it doesn't know" do
      expect(error_for(page_limit: 5)).to eq("Unknown server settings: page_limit")
    end

    it "refuses a path that isn't absolute, or ends in a slash or query" do
      expect(error_for(path: "mcp")).to start_with("path must be an absolute path")
      expect(error_for(path: "/mcp/")).to start_with("path must be")
      expect(error_for(path: "/mcp?x=1")).to start_with("path must be")
    end

    it "refuses a blank name, version, title or instructions" do
      expect(error_for(name: " ")).to start_with("name must be a non-empty string")
      expect(error_for(version: 1)).to start_with("version must be a non-empty string")
      expect(error_for(title: "")).to start_with("title must be")
      expect(error_for(instructions: "")).to start_with("instructions must be")
    end

    it "refuses limits that aren't positive integers" do
      expect(error_for(max_body_bytes: 0)).to start_with("max_body_bytes must be a positive integer")
      expect(error_for(page_size: 2.5)).to start_with("page_size must be")
      expect(error_for(max_page_size: "100")).to start_with("max_page_size must be")
    end

    it "refuses a page size larger than the largest page" do
      expect(error_for(page_size: 50, max_page_size: 10)).to eq("page_size (50) can't be larger than max_page_size (10)")
    end

    it "refuses tool_verbs that aren't a hash of non-empty strings" do
      expect(error_for(tool_verbs: ["list"])).to start_with("tool_verbs must be a hash")
      expect(error_for(tool_verbs: { index: "" })).to start_with("tool_verbs[:index] must be")
    end

    it "is an ArgumentError" do
      expect { described_class.new(page_size: 0) }.to raise_error(ArgumentError)
    end
  end
end
