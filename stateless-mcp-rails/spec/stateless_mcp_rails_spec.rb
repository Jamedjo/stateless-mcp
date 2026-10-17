RSpec.describe StatelessMcp::Rails do
  it "loads beside the core gem, at the same version" do
    expect(StatelessMcp::VERSION).to eq(Gem::Specification.load(File.expand_path("../stateless-mcp-rails.gemspec", __dir__)).version.to_s)
  end

  it "leaves the framework reachable as ::Rails" do
    expect(::Rails::VERSION::MAJOR).to be >= 7
  end
end
