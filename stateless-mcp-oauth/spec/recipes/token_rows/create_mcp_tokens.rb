# db/migrate/20261019000001_create_mcp_tokens.rb
class CreateMcpTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_tokens do |t|
      t.references :mcp_grant, type: :string # none for an authorization code
      t.string :token_id, null: false, index: { unique: true }
      t.string :digest, null: false, index: { unique: true }
      t.string :kind, null: false
      t.json :authorization_request # an authorization code's
      t.json :approved_by # an authorization code's
      t.datetime :expires_at, null: false
      t.datetime :used_at # a refresh token, once exchanged
      t.datetime :revoked_at
      t.timestamps
    end
  end
end
