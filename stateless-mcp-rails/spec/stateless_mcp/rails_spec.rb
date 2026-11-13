RSpec.describe StatelessMcp::Rails do
  it "loads beside the core gem, at the same version" do
    expect(StatelessMcp::VERSION).to eq(Gem::Specification.load(File.expand_path("../../stateless-mcp-rails.gemspec", __dir__)).version.to_s)
  end

  it "ships the repository's licences, unchanged" do
    %w[LICENSE-MIT LICENSE-APACHE].each do |file|
      expect(File.read(File.join(__dir__, "../..", file))).to eq(File.read(File.join(__dir__, "../../..", file)))
    end
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

    it "builds the server when protected_resource is set, since every request then needs an access token" do
      expect(described_class.build_default_server({ protected_resource: -> { nil } }, default_name: "notes")).to have_attributes(name: "notes")
    end

    it "builds an open server when allow_unauthenticated is true" do
      expect(described_class.build_default_server({ parent_controller: "ActionController::API", allow_unauthenticated: true }, default_name: "notes")).to have_attributes(name: "notes")
    end
  end

  it "puts the default server's middleware on the app's stack" do
    expect(Rails.application.middleware.middlewares.map(&:klass).count(StatelessMcp::Middleware)).to eq(2)
  end

  describe ".use_middleware" do
    let(:server) { StatelessMcp::Server.new(name: "notes") }

    it "puts the token check before the MCP middleware when there's a protected resource" do
      stack = ActionDispatch::MiddlewareStack.new
      described_class.use_middleware(stack, server, protected_resource: -> { nil })

      expect(stack.middlewares.map(&:klass)).to eq([StatelessMcp::OAuth::RequireToken, StatelessMcp::Middleware])
    end

    it "gives controllers the grant the token check found, as mcp_grant" do
      controller = Class.new(ActionController::API) { include StatelessMcp::Rails::Controller; public :mcp_grant }.new
      controller.request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/mcp", "stateless_mcp.oauth.grant" => :the_grant))

      expect(controller.mcp_grant).to eq(:the_grant)
    end

    it "raises from mcp_grant when the setting is on but no grant arrived, as the token check must be missing" do
      controller = Class.new(ActionController::API) { include StatelessMcp::Rails::Controller; public :mcp_grant }.new
      controller.request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/mcp", method: "POST", StatelessMcp::Server::ENV_KEY => server))
      allow(described_class).to receive(:protected_resource).and_return(Object.new)

      expect { controller.mcp_grant }.to raise_error(described_class::MissingGrant, /RequireToken/)
    end

    it "gives nil from mcp_grant on another route to the same controller, which the token check doesn't cover" do
      controller = Class.new(ActionController::API) { include StatelessMcp::Rails::Controller; public :mcp_grant }.new
      controller.request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/api/notes", method: "POST"))
      allow(described_class).to receive(:protected_resource).and_return(Object.new)

      expect(controller.mcp_grant).to be_nil
    end

    it "adds only the MCP middleware without one" do
      stack = ActionDispatch::MiddlewareStack.new
      described_class.use_middleware(stack, server)

      expect(stack.middlewares.map(&:klass)).to eq([StatelessMcp::Middleware])
    end
  end
end
