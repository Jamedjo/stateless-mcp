RSpec.describe StatelessMcp do
  it "loads with the mcp gem" do
    expect(StatelessMcp::VERSION).to eq("0.0.1")
    expect(defined?(MCP::Tool)).to be_truthy
  end

  it "ships the repository's licences, unchanged" do
    %w[LICENSE-MIT LICENSE-APACHE].each do |file|
      expect(File.read(File.join(__dir__, "..", file))).to eq(File.read(File.join(__dir__, "../..", file)))
    end
  end
end
