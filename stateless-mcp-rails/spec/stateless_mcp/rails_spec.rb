RSpec.describe StatelessMcp::Rails do
  it "loads beside the core gem, at the same version" do
    expect(StatelessMcp::VERSION).to eq(Gem::Specification.load(File.expand_path("../../stateless-mcp-rails.gemspec", __dir__)).version.to_s)
  end

  it "builds the default server from config.stateless_mcp" do
    expect(described_class.default_server).to have_attributes(path: "/mcp", name: "notes", version: "2.0.0", max_body_bytes: 4096, page_size: 2, max_page_size: 100)
  end

  describe "the authentication check at boot" do
    it "boots an app that sets parent_controller to its own base controller, as the dummy app does" do
      expect(Rails.application.config.stateless_mcp.parent_controller).to eq("Mcp::BaseController")
      expect(described_class.build_default_server({ parent_controller: "Mcp::BaseController" }, default_name: "notes")).to be_a(StatelessMcp::Server)
    end

    it "refuses to build the default server with neither setting, naming both" do
      [{}, { parent_controller: "ActionController::API", allow_unauthenticated: false }].each do |settings|
        expect { described_class.build_default_server(settings, default_name: "notes") }.to raise_error(described_class::AuthenticationNotConfigured, /config\.stateless_mcp\.parent_controller to a controller that authenticates.*allow_unauthenticated = true/)
      end
    end

    it "builds an open server when allow_unauthenticated is true" do
      expect(described_class.build_default_server({ parent_controller: "ActionController::API", allow_unauthenticated: true }, default_name: "notes")).to have_attributes(name: "notes")
    end
  end

  it "puts the default server's middleware on the app's stack" do
    expect(Rails.application.middleware.middlewares.map(&:klass).count(StatelessMcp::Middleware)).to eq(2)
  end
end
