RSpec.describe StatelessMcp::OAuth do
  it "loads stateless-mcp" do
    expect(defined?(StatelessMcp::Server)).to be_truthy
  end

  it "ships the repository's licences, unchanged" do
    %w[LICENSE-MIT LICENSE-APACHE].each do |file|
      expect(File.read(File.join(__dir__, "../..", file))).to eq(File.read(File.join(__dir__, "../../..", file)))
    end
  end
end
