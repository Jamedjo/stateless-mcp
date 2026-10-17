RSpec.describe StatelessMcp do
  it "loads with the mcp gem" do
    expect(StatelessMcp::VERSION).to eq("0.1.0")
    expect(defined?(MCP::Tool)).to be_truthy
  end
end
