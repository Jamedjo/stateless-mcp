# db/migrate/20261019000001_add_refresh_token_id_to_mcp_grants.rb
class AddRefreshTokenIdToMcpGrants < ActiveRecord::Migration[8.1]
  def change
    add_column :mcp_grants, :refresh_token_id, :string
  end
end
