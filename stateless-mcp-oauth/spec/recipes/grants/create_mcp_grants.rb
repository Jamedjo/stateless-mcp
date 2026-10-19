# db/migrate/20261019000000_create_mcp_grants.rb
class CreateMcpGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_grants, id: :string do |t|
      t.references :user, null: false
      t.string :client_id, null: false
      t.string :resource, null: false
      t.string :scope, null: false
      t.datetime :revoked_at
      t.timestamps
    end
  end
end
