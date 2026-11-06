require "action_controller"
require "stateless_mcp/rails/controller"
require "rack/test"
require_relative "../../stateless-mcp/spec/support/mcp_requests"

# The usage examples in docs/oauth.md, each run as an app would have it.
module UsageRecipe
  DIR = File.join(__dir__, "recipes/usage")

  # Stands in for the app's storage class, with one good access token, and
  # one for each way a token can be refused.
  class McpOAuthStorage < StatelessMcp::OAuth::Storage
    Grant = Struct.new(:id, :client_id, :resource, :scope, :user_id)
    GRANTS = {
      "g1" => Grant.new("g1", "https://client.example/metadata.json", "https://notes.example/mcp", "notes:read", 42),
      "elsewhere" => Grant.new("elsewhere", "https://client.example/metadata.json", "https://notes.example/admin/mcp", "admin", 42)
    }.freeze
    TOKENS = {
      "good" => { kind: "access", grant_id: "g1" },
      "expired" => { kind: "access", grant_id: "g1", expires_at: Time.now.to_i - 1 },
      "revoked" => { kind: "access", grant_id: "revoked" },
      "refresh" => { kind: "refresh", grant_id: "g1" },
      "elsewhere" => { kind: "access", grant_id: "elsewhere" }
    }.freeze

    def read_token(token)
      { id: "t1", expires_at: Time.now.to_i + 3600 }.merge(TOKENS.fetch(token)) if TOKENS.key?(token)
    end

    def find_grant(id)
      GRANTS[id]
    end
  end

  module Mcp; end

  def self.load(file)
    module_eval(File.read(File.join(DIR, file)), File.join(DIR, file))
  end

  load "mcp_oauth.rb"
  module_eval(File.read(File.join(__dir__, "recipes/server/mcp_oauth_server.rb")), File.join(__dir__, "recipes/server/mcp_oauth_server.rb"))
  load "base_controller.rb"

  class NotesController < Mcp::BaseController
    def show
      render plain: "user #{@mcp_grant.user_id}"
    end
  end

  ROUTES = ActionDispatch::Routing::RouteSet.new
  module_eval(<<~RUBY, File.join(DIR, "routes.rb"))
    ROUTES.draw do
      #{File.read(File.join(DIR, "routes.rb"))}
      #{File.read(File.join(__dir__, "recipes/server/routes.rb"))}
      #{File.read(File.join(__dir__, "recipes/server/token_routes.rb"))}
      post "/mcp", to: NotesController.action(:show)
    end
  RUBY

  RACK_APP = module_eval("Rack::Builder.new { #{File.read(File.join(__dir__, "recipes/server/config.ru"))}\n#{File.read(File.join(__dir__, "recipes/server/token_config.ru"))}\nrun ->(_env) { [404, {}, []] } }", File.join(__dir__, "recipes/server/config.ru"))
end

RSpec.describe "The OAuth usage examples" do
  include Rack::Test::Methods
  include McpRequests

  shared_examples "an app checking MCP requests" do
    it "lets a request with a valid access token through, with its grant" do
      post_mcp "/mcp", "tools/list", headers: { "HTTP_AUTHORIZATION" => "Bearer good" }

      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("user 42")
    end

    it "answers a request without a token with a 401 that points at the metadata" do
      post_mcp "/mcp", "tools/list"

      expect(last_response.status).to eq(401)
      expect(last_response.headers["www-authenticate"]).to eq('Bearer resource_metadata="https://notes.example/.well-known/oauth-protected-resource/mcp"')
    end

    it "says the token was refused when one was sent" do
      post_mcp "/mcp", "tools/list", headers: { "HTTP_AUTHORIZATION" => "Bearer forged" }

      expect(last_response.status).to eq(401)
      expect(last_response.headers["www-authenticate"]).to end_with(', error="invalid_token"')
    end

    it "answers every refused token the same way, so the client can't tell why" do
      responses = %w[forged expired revoked refresh elsewhere].to_h do |token|
        post_mcp "/mcp", "tools/list", headers: { "HTTP_AUTHORIZATION" => "Bearer #{token}" }
        [token, [last_response.status, last_response.headers.to_h.except("x-request-id", "x-runtime", "date"), last_response.body]]
      end

      expect(responses.values.uniq).to eq([responses["forged"]]), responses.inspect
    end

    it "serves the OAuth server's metadata at the URL the protected resource metadata lists" do
      get "/.well-known/oauth-authorization-server"

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to include("issuer" => "https://notes.example", "token_endpoint" => "https://notes.example/oauth/token")
    end

    it "serves the token endpoint" do
      post "/oauth/token", grant_type: "authorization_code", client_id: "https://claude.ai/client.json", code: "nonsense"

      expect(last_response.status).to eq(400)
      expect(JSON.parse(last_response.body)).to include("error" => "invalid_grant")
    end

    it "serves the metadata the 401 points at" do
      get "/.well-known/oauth-protected-resource/mcp"

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to include("resource" => "https://notes.example/mcp", "authorization_servers" => ["https://notes.example"])
    end
  end

  describe "in Rails, with a before_action" do
    def app
      UsageRecipe::ROUTES
    end

    it_behaves_like "an app checking MCP requests"
  end

  describe "in Rack, with a map" do
    def app
      UsageRecipe::RACK_APP
    end

    it "serves the OAuth server's metadata" do
      get "/.well-known/oauth-authorization-server"

      expect(JSON.parse(last_response.body)).to include("issuer" => "https://notes.example")
    end
  end
end

RSpec.describe "The egress proxy example" do
  it "fetches client metadata documents through the proxy" do
    server = Module.new
    server.const_set(:MCP_OAUTH, UsageRecipe::MCP_OAUTH)
    recipe = File.join(__dir__, "recipes/server/egress_proxy.rb")
    stub_const("ENV", ENV.to_h.merge("EGRESS_PROXY_URL" => "http://smokescreen.internal:4750"))
    server.module_eval(File.read(recipe), recipe)
    allow(Net::HTTP).to receive(:start).and_raise(SocketError, "stopped at the proxy")

    expect { server::MCP_OAUTH_SERVER.client("https://claude.ai/oauth/mcp-oauth-client-metadata") }.to raise_error(StatelessMcp::OAuth::Error)
    expect(Net::HTTP).to have_received(:start).with("claude.ai", 443, "smokescreen.internal", 4750, nil, nil, hash_including(use_ssl: true))
  end
end
