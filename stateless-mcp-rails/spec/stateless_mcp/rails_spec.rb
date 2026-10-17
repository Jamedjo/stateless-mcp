RSpec.describe StatelessMcp::Rails do
  it "loads beside the core gem, at the same version" do
    expect(StatelessMcp::VERSION).to eq(Gem::Specification.load(File.expand_path("../../stateless-mcp-rails.gemspec", __dir__)).version.to_s)
  end

  it "builds the default server from config.stateless_mcp" do
    expect(described_class.default_server).to have_attributes(path: "/mcp", name: "notes", version: "2.0.0", max_body_bytes: 4096, page_size: 2, max_page_size: 100)
  end

  it "puts the default server's middleware on the app's stack" do
    expect(Rails.application.middleware.middlewares.map(&:klass).count(StatelessMcp::Middleware)).to eq(2)
  end
end
