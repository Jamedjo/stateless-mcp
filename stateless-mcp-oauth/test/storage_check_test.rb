# The Minitest adapter, run against the encrypted tokens and token rows
# examples. The RSpec suite runs the same examples through the RSpec adapter.
require "minitest/autorun"
require "stateless-mcp-oauth"
require "stateless_mcp/oauth/storage_check/minitest"
require "active_record"
require "active_support/message_encryptor"
require "tmpdir"
require_relative "../spec/support/oauth_recipes"

# A database file, since the race checks need database connections from several threads.
DATABASE_DIR = Dir.mktmpdir
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: File.join(DATABASE_DIR, "oauth.sqlite3"), pool: 10, timeout: 5000)
OAuthRecipes.migrate(OAuthRecipes::Encrypted::CreateMcpGrants, OAuthRecipes::Encrypted::AddRefreshTokenIdToMcpGrants, OAuthRecipes::TokenRows::CreateMcpTokens)
Minitest.after_run { FileUtils.remove_entry(DATABASE_DIR) }

class EncryptedTokensStorageTest < Minitest::Test
  include StatelessMcp::OAuth::StorageCheck::Minitest

  def storage
    OAuthRecipes::Encrypted::McpOAuthStorage.new
  end

  def approved_by
    { user_id: 42 }
  end
end

class TokenRowsStorageTest < Minitest::Test
  include StatelessMcp::OAuth::StorageCheck::Minitest

  def storage
    OAuthRecipes::TokenRows::McpOAuthStorage.new
  end

  def approved_by
    { user_id: 42 }
  end
end

# A storage class with a bug, to show the adapter fails a test that should fail.
class BrokenStorageTest < Minitest::Test
  def test_a_failing_check_fails_the_test
    broken = Class.new(OAuthRecipes::TokenRows::McpOAuthStorage) do
      def consume_refresh_token(_claims)
        true
      end
    end
    test_class = Class.new(Minitest::Test) do
      include StatelessMcp::OAuth::StorageCheck::Minitest

      define_method(:storage) { broken.new }
      define_method(:approved_by) { { user_id: 42 } }
    end

    result = test_class.new("test_storage_consume_once").run

    refute result.passed?
    assert_match(/didn't return false the second time/, result.failure.message)
  end
end
