require "action_controller"
require "action_view"
require "rack/test"

# Runs the consent page example from docs/oauth.md in Rails, as an app would,
# with a signed-in person.
module ConsentRecipe
  RECIPES = File.join(__dir__, "recipes")

  # Stands in for the app's storage class, keeping each authorization code's
  # claims.
  class McpOAuthStorage < StatelessMcp::OAuth::Storage
    CODES = {}

    def issue_token(claims)
      SecureRandom.hex(8).tap { |token| CODES[token] = claims }
    end
  end

  # Stands in for the app's base controller and sign-in.
  class ApplicationController < ActionController::Base
    User = Struct.new(:id)

    skip_forgery_protection
    prepend_view_path File.join(RECIPES, "consent/views")

    private
      def authenticate_user!
        head :unauthorized unless current_user
      end

      def current_user
        User.new(7) if request.headers["X-Signed-In"]
      end
  end

  %w[usage/mcp_oauth.rb server/mcp_oauth_server.rb consent/mcp_authorizations_controller.rb].each do |file|
    module_eval(File.read(File.join(RECIPES, file)), File.join(RECIPES, file))
  end

  # McpAuthorizationsController's views are under mcp_authorizations/, where an
  # app keeps them, instead of under consent_recipe/.
  McpAuthorizationsController.define_singleton_method(:controller_path) { "mcp_authorizations" }

  ROUTES = ActionDispatch::Routing::RouteSet.new
  module_eval(<<~RUBY, File.join(RECIPES, "consent/routes.rb"))
    ROUTES.draw do
      scope module: "consent_recipe" do
        #{File.read(File.join(RECIPES, "consent/routes.rb"))}
      end
    end
  RUBY
end

RSpec.describe "The consent page example" do
  include Rack::Test::Methods

  let(:client_id) { "https://claude.ai/oauth/mcp-oauth-client-metadata" }
  let(:redirect_uri) { "https://claude.ai/api/mcp/auth_callback" }
  let(:document) { { client_id: client_id, client_name: "Claude", redirect_uris: [redirect_uri] } }
  let(:query) { { response_type: "code", client_id: client_id, redirect_uri: redirect_uri, code_challenge: StatelessMcp::OAuth::Pkce.challenge_for("v" * 43), code_challenge_method: "S256", state: "xyz", resource: "https://notes.example/mcp" } }

  def app
    ConsentRecipe::ROUTES
  end

  before do
    allow(StatelessMcp::OAuth::ClientMetadata).to receive(:fetch) { |id, **| StatelessMcp::OAuth::ClientMetadata.parse(id, JSON.generate(document)) }
    header "X-Signed-In", "yes"
  end

  def redirect_query
    URI.decode_www_form(URI(last_response.location).query).to_h
  end

  it "shows the client and where the person goes back to, with Allow and Deny" do
    get "/oauth/authorize", query

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("Allow Claude to use your notes?", "<strong>claude.ai</strong>", "Allow", "Deny")
    expect(last_response.body).to include(%(name="state" value="xyz"))
  end

  it "redirects with an authorization code on Allow, with the person as approved_by" do
    post "/oauth/authorize", query.merge(decision: "approve")

    expect(last_response.status).to eq(302)
    expect(last_response.location).to start_with(redirect_uri)
    code = redirect_query.fetch("code")
    expect(ConsentRecipe::McpOAuthStorage::CODES.fetch(code)[:approved_by]).to eq(user_id: 7)
  end

  it "sends the person back with access_denied when they deny it" do
    post "/oauth/authorize", query.merge(decision: "deny")

    expect(redirect_query).to include("error" => "access_denied", "state" => "xyz")
  end

  it "sends a problem back to the client" do
    get "/oauth/authorize", query.merge(code_challenge_method: "plain")

    expect(redirect_query).to include("error" => "invalid_request", "state" => "xyz")
  end

  it "shows the person an error for a redirect URI the client didn't list, without redirecting" do
    get "/oauth/authorize", query.merge(redirect_uri: "https://attacker.example/callback")

    expect(last_response.status).to eq(400)
    expect(last_response.body).to eq("redirect_uri isn't one claude.ai listed")
  end

  it "needs the person signed in to the app" do
    header "X-Signed-In", nil
    get "/oauth/authorize", query

    expect(last_response.status).to eq(401)
  end
end
