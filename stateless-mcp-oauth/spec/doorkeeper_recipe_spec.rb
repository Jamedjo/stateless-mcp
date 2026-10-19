# The Doorkeeper recipe in docs/oauth-storage-moving.md, against the
# doorkeeper gem. Run it with the gemfile Appraisal generates:
#
#   BUNDLE_GEMFILE=gemfiles/doorkeeper.gemfile bundle exec rspec spec/doorkeeper_recipe_spec.rb
return unless Gem.loaded_specs.key?("doorkeeper")

require "erb"
require "rails"
require "active_record"
require "doorkeeper"
require "tmpdir"
require_relative "support/oauth_recipes"

OAuthRecipes.build :FromDoorkeeper, *OAuthRecipes::GRANTS, *OAuthRecipes::TOKEN_ROWS, "doorkeeper/read_token.rb", "doorkeeper/use_up_tokens.rb"

RSpec.describe "The Doorkeeper recipe" do
  before(:all) do
    @dir = Dir.mktmpdir
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: File.join(@dir, "doorkeeper.sqlite3"), pool: 10, timeout: 5000)
    Doorkeeper.configure { orm :active_record }
    Doorkeeper.run_orm_hooks
    ActiveRecord::Schema.verbose = false
    ActiveRecord::Schema.define { create_table(:users) }
    # Doorkeeper's migration, rendered from its generator template.
    template = File.join(Gem.loaded_specs["doorkeeper"].full_gem_path, "lib/generators/doorkeeper/templates/migration.rb.erb")
    eval(ERB.new(File.read(template)).result_with_hash(migration_version: "[8.1]"), TOPLEVEL_BINDING, template) # rubocop:disable Security/Eval
    OAuthRecipes.migrate(CreateDoorkeeperTables, OAuthRecipes::FromDoorkeeper::CreateMcpGrants, OAuthRecipes::FromDoorkeeper::CreateMcpTokens)
  end

  after(:all) do
    ActiveRecord::Base.remove_connection
    FileUtils.remove_entry(@dir)
  end

  let(:storage) { OAuthRecipes::FromDoorkeeper::McpOAuthStorage.new }
  let(:application) { Doorkeeper::Application.create!(name: "Client", redirect_uri: "https://client.example/callback") }
  let(:doorkeeper_token) { Doorkeeper::AccessToken.create!(application:, resource_owner_id: 7, scopes: "notes:read", expires_in: 3600, use_refresh_token: true) }

  def symbolize(claims)
    StatelessMcp::OAuth::Claims.symbolize(claims)
  end

  it_behaves_like "stateless-mcp oauth storage" do
    let(:approved_by) { { user_id: 42 } }
  end

  it "reads a Doorkeeper access token, recording its grant the first time" do
    claims = symbolize(storage.read_token(doorkeeper_token.token))

    expect(claims).to include(kind: "access", grant_id: "doorkeeper-#{application.id}-7")
    expect(storage.find_grant(claims[:grant_id])).to have_attributes(user_id: 7, client_id: application.uid, scope: "notes:read")
    expect(StatelessMcp::OAuth::Claims.from_h(claims)).not_to be_expired
  end

  it "consumes a Doorkeeper refresh token only once" do
    refresh = symbolize(storage.read_token(doorkeeper_token.refresh_token))

    expect(refresh).to include(kind: "refresh")
    expect(storage.consume_refresh_token(refresh)).to be(true)
    expect(storage.consume_refresh_token(refresh)).to be(false)
    expect(symbolize(storage.read_token(doorkeeper_token.refresh_token))).to include(kind: "refresh")
  end

  it "revokes one Doorkeeper token and keeps its grant" do
    claims = symbolize(storage.read_token(doorkeeper_token.token))

    storage.revoke_token(claims)

    expect(storage.read_token(doorkeeper_token.token)).to be_nil
    expect(storage.find_grant(claims[:grant_id])).not_to be_nil
  end

  it "reads Doorkeeper tokens stored hashed, with hash_token_secrets" do
    Doorkeeper.configure { orm :active_record; hash_token_secrets }
    token = Doorkeeper::AccessToken.create!(application:, resource_owner_id: 8, expires_in: 3600, use_refresh_token: true)

    expect(token.token).not_to eq(token.plaintext_token)
    expect(symbolize(storage.read_token(token.plaintext_token))).to include(kind: "access")
    expect(symbolize(storage.read_token(token.plaintext_refresh_token))).to include(kind: "refresh")
  ensure
    Doorkeeper.configure { orm :active_record }
  end

  it "returns nil for a revoked Doorkeeper token" do
    doorkeeper_token.revoke

    expect(storage.read_token(doorkeeper_token.token)).to be_nil
  end
end
