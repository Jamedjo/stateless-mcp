RSpec.describe StatelessMcp::Rails::Routing do
  let(:server) { StatelessMcp::Server.new(path: "/tools", tool_verbs: { index: "find" }) }

  def draw(&block)
    routes = ActionDispatch::Routing::RouteSet.new
    routes.draw(&block)
    routes
  end

  def tool_names(routes, server)
    described_class.tools(server, routes).map(&:first)
  end

  it "names a resource's tools by the server's tool_verbs" do
    server = self.server
    routes = draw { mcp_server(server, module: "mcp") { mcp_resource :notes, only: [:index, :show] } }

    expect(tool_names(routes, server)).to eq(["find_notes", "get_note"])
  end

  it "routes the protocol's own methods to the server controller, or to one the app gives" do
    server = self.server
    routes = draw { mcp_server(server, controller: "tools_server") { } }

    expect(routes.routes.map { |route| route.defaults[:controller] }.uniq).to eq(["tools_server"])
  end

  it "refuses an action with no tool verb" do
    server = self.server

    expect { draw { mcp_server(server) { mcp_resource :notes, only: [:archive] } } }.to raise_error(ArgumentError, /No tool verb for :archive/)
  end

  it "refuses mcp_member outside a resource" do
    server = self.server

    expect { draw { mcp_server(server) { mcp_member :body } } }.to raise_error(ArgumentError, /inside an mcp_resource block/)
  end

  it "refuses a tool outside mcp_server" do
    expect { draw { mcp_tool "search", to: "search#show" } }.to raise_error(ArgumentError, /inside an mcp_server block/)
  end

  it "refuses to draw inside a path scope, where the server's path would move" do
    server = self.server

    expect { draw { scope("/api") { mcp_server(server) { } } } }.to raise_error(ArgumentError, %r{draws at its server's own path, /tools})
  end
end
