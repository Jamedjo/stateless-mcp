# OAuth storage

With `stateless-mcp-oauth`, the app controls how grants and tokens are stored and encrypted. Grants can sit in the app's database beside its users. Tokens can be encrypted with a library the app already uses and holds keys for, or kept as rows with no encryption at all. The app subclasses `StatelessMcp::OAuth::Storage` and defines a few methods, and the gem calls them.

[How the OAuth gem works](oauth.md) covers the full sign-in. This page covers storage.

## What gets stored

- **A grant** is one person allowing one client, such as Claude, to use one MCP server.
- **An authorization code** is what the client gets once the person approves. It lasts two minutes, and the client exchanges it once for its first access token and refresh token. That exchange creates the grant.
- **An access token** is sent with each MCP request. It lasts an hour.
- **A refresh token** is exchanged for a new access token and a new refresh token when the access token expires. Each refresh token can be used once.

Authorization codes, access tokens and refresh tokens all belong to a grant.

## The methods

### Grants

```ruby
create_grant(code_id:, authorization_request:, approved_by:) # => the new grant's id, or nil
find_grant(id)                                               # => the grant, or nil
revoke_grant(id)
```

- **`create_grant`** runs when a client exchanges an authorization code for its first tokens. It returns the new grant's id as a String. The storage chooses the id. The examples use the authorization code's id, which is the simplest way to meet the requirements below.
- **Each authorization code works once.** `create_grant` must return `nil` for a `code_id` it has seen before, changing nothing. That includes a `code_id` whose grant was revoked, and two requests racing to exchange the same authorization code: exactly one gets a grant id. A unique column and an `insert` that skips a taken value meets all three.
- **Each grant id is different.** Two authorization codes never share a grant.
- **`authorization_request`** is what the client asked for and the person approved: `{ client_id:, resource:, scope: }`.
- **`approved_by`** is whatever attributes the app passed when the person approved, such as `{ user_id: 42 }`, or `{ org_id:, bot_id: }`. The gem never reads them, and the app reads them back from its own grant. The storage can keep the two hashes in one table or split them, such as with a table of clients.
- **`find_grant`** returns the app's own object for the grant. The gem only calls `client_id`, `resource` and `scope` on it. It returns `nil` once the grant is revoked.
- **`revoke_grant`** ends the grant and every token in it.

### Tokens

```ruby
issue_token(claims)           # => the token string
issue_tokens(access, refresh) # optional; => both token strings
read_token(token)             # => the claims, or nil
consume_refresh_token(claims) # => true the first time, then false
revoke_token(claims)          # optional
```

The gem passes each token's details, its *claims*, to `issue_token` as a hash:

```ruby
{ kind: "refresh", id: "6b0e...", grant_id: "f3a1...", expires_at: 1792000000 }
```

`kind` is `"code"` for an authorization code, `"access"` or `"refresh"`. An authorization code's claims have no `grant_id`, because its grant is created when it's exchanged. They have `authorization_request` and `approved_by` instead. The authorization request also has the `redirect_uri` and `code_challenge` the token endpoint checks.

- **`issue_token`** returns the string the client is given. It can add keys of its own to the claims.
- **`issue_tokens`** issues an access token and a refresh token together, when an authorization code or a refresh token is exchanged. It's optional: by default it calls `issue_token` for each. Override it to store the pair together, or to note the newest refresh token on the grant, as the encrypted tokens example does.
- **`read_token`** returns the claims for a token string, including any keys `issue_token` added. It returns `nil` for a token it didn't issue, or one that was revoked. The gem validates the claims and checks expiry.
- **`consume_refresh_token`** marks a refresh token used. It returns `true` the first time and `false` after that, even when two requests race. `false` means the refresh token was copied, so the gem revokes the grant.
- **A used refresh token still reads.** `read_token` must return its claims, not `nil`, or the gem can't tell when it's used again. Mark it used, rather than revoked.
- **`revoke_token`** is optional. By default it revokes the token's grant, which fails safe.

### Errors and transactions

- **Each method must be atomic.** A single statement is enough, such as an `insert` that skips a taken id, or an `update` with a `where`. The gem doesn't wrap calls in a transaction, so storage can use any database.
- **Raise on errors.** The gem doesn't rescue them, and the request fails. Never return `false` from `consume_refresh_token` for an error, because `false` revokes the grant.
- **The gem orders its calls to fail safe.** On a refresh, it consumes the old refresh token before issuing new tokens. If issuing fails, the client has to sign in again, but no token works twice.

## Testing

`StatelessMcp::OAuth::StorageCheck` checks a storage class against everything above, including two requests racing to use the same authorization code or refresh token. It calls every method a sign-in needs, so a missing method fails in the tests, before anyone signs in.

It lives in the gem's `test_support` folder, not `lib`, so only an app's tests load it. Thin adapters turn each check into a test. `approved_by` is the attributes the app's grants keep.

With Minitest:

```ruby
require "stateless_mcp/oauth/storage_check/minitest"

class McpOAuthStorageTest < ActiveSupport::TestCase
  include StatelessMcp::OAuth::StorageCheck::Minitest

  def storage
    McpOAuthStorage.new
  end

  def approved_by
    { user_id: 42 }
  end
end
```

With RSpec:

```ruby
require "stateless_mcp/oauth/storage_check/rspec"

RSpec.describe McpOAuthStorage do
  it_behaves_like "stateless-mcp oauth storage" do
    let(:storage) { McpOAuthStorage.new }
    let(:approved_by) { { user_id: 42 } }
  end
end
```

Any other framework can call `StatelessMcp::OAuth::StorageCheck.new(storage, approved_by:).run_all`, which raises at the first failure.

The race checks use threads, so every database connection must reach the same database. A SQLite file works. An in-memory SQLite database doesn't.

## Examples

These are complete, tested ActiveRecord examples. Each is one way to meet the methods above, not something the gem requires.

There are two common ways to store tokens:

- **Encrypted tokens.** The token is its claims, encrypted with a key from the app. Nothing is stored per token. Revoking a token revokes its grant. Changing the key ends every token.
- **Token rows.** Each token has a row. A single token can be revoked, and a grant's tokens can be listed. No key is needed, but expired rows have to be deleted.

Encrypted tokens are the simpler place to start. [Moving OAuth storage](oauth-storage-moving.md) has examples for switching between them, and for moving from Doorkeeper.

### Example: grants table

Both token examples use this. The app approves with `user_id`, so the grants table has a `user_id` column:

```ruby
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
```

```ruby
# app/models/mcp_grant.rb
class McpGrant < ApplicationRecord
  belongs_to :user
end
```

```ruby
# app/models/mcp_oauth_storage.rb
class McpOAuthStorage < StatelessMcp::OAuth::Storage
  # The grant takes the authorization code's id. insert skips an id that's
  # taken, returning no rows, so each authorization code creates at most one
  # grant. This app approves with user_id.
  def create_grant(code_id:, authorization_request:, approved_by:)
    code_id if McpGrant.insert({ id: code_id, **authorization_request, user_id: approved_by[:user_id] }).any?
  end

  def find_grant(id)
    McpGrant.find_by(id:, revoked_at: nil)
  end

  def revoke_grant(id)
    McpGrant.where(id:).update_all(revoked_at: Time.current)
  end
end
```

MySQL can't return the inserted row, so there this example refuses every sign-in, and `StorageCheck` fails. Use `create!` and rescue `ActiveRecord::RecordNotUnique` instead.

### Example: encrypted tokens

The token is the claims hash, encrypted with `ActiveSupport::MessageEncryptor`. Rails uses the same library to encrypt its cookies. The grant stores the id of its newest refresh token, so only that refresh token can be used, and only once:

```ruby
# db/migrate/20261019000001_add_refresh_token_id_to_mcp_grants.rb
class AddRefreshTokenIdToMcpGrants < ActiveRecord::Migration[8.1]
  def change
    add_column :mcp_grants, :refresh_token_id, :string
  end
end
```

```ruby
# app/models/mcp_oauth_storage.rb
class McpOAuthStorage < StatelessMcp::OAuth::Storage
  def issue_token(claims)
    encryptor.encrypt_and_sign(claims, purpose: :mcp_oauth_token)
  end

  # Only the grant's newest refresh token can be used, so the grant notes its id.
  def issue_tokens(access, refresh)
    McpGrant.where(id: refresh[:grant_id]).update_all(refresh_token_id: refresh[:id])
    super
  end

  def read_token(token)
    encryptor.decrypt_and_verify(token, purpose: :mcp_oauth_token)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  # Only the grant's newest refresh token can be used, and only once.
  def consume_refresh_token(claims)
    McpGrant.where(id: claims[:grant_id], refresh_token_id: claims[:id], revoked_at: nil)
            .update_all(refresh_token_id: nil) == 1
  end

  private
    # A separate key, derived from the app's secret_key_base.
    def encryptor
      @encryptor ||= ActiveSupport::MessageEncryptor.new(
        Rails.application.key_generator.generate_key("mcp oauth tokens", 32),
        cipher: "aes-256-gcm", serializer: :json, url_safe: true
      )
    end
end
```

- **The key** is derived from the app's `secret_key_base`, so there's no new secret to keep.
- **The purpose** stops a token being accepted anywhere else the app uses the same key.
- **`url_safe`** makes tokens safe to send in a header or a form.

**Changing the key** ends every token. If the key leaks, change it. For a planned change, keep old tokens working with `encryptor.rotate`, which reads them with the old key until they expire.

**Outside Rails:** the `activesupport` gem works without Rails. [Lockbox](https://github.com/ankane/lockbox) and [RbNaCl](https://github.com/RubyCrypto/rbnacl) are alternatives.

### Example: token rows

Each token has a row, holding a digest of the token rather than the token itself.

- **Choose it** to revoke one token without ending its grant, to list a grant's tokens, or to avoid managing a key. Apps coming from Doorkeeper already store tokens this way.
- **Skip it** to keep one table, with nothing to clean up and one query per request instead of two.

```ruby
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
```

```ruby
# app/models/mcp_token.rb
class McpToken < ApplicationRecord
  # An authorization code's row is written before its grant exists.
  belongs_to :mcp_grant, optional: true

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def claims
    { kind:, id: token_id, grant_id: mcp_grant_id, expires_at: expires_at.to_i, authorization_request:, approved_by: }
  end
end
```

```ruby
# app/models/mcp_oauth_storage.rb
class McpOAuthStorage < StatelessMcp::OAuth::Storage
  # A random token, kept only as its digest.
  def issue_token(claims)
    token = SecureRandom.urlsafe_base64(32)
    McpToken.create!(digest: McpToken.digest(token), token_id: claims[:id], mcp_grant_id: claims[:grant_id],
                     kind: claims[:kind], expires_at: Time.at(claims[:expires_at]),
                     authorization_request: claims[:authorization_request], approved_by: claims[:approved_by])
    token
  end

  def read_token(token)
    McpToken.find_by(digest: McpToken.digest(token), revoked_at: nil)&.claims
  end

  # A used refresh token's row is marked used, not revoked, so it still reads
  # and the gem can tell when it's used again.
  def consume_refresh_token(claims)
    McpToken.where(token_id: claims[:id], used_at: nil, revoked_at: nil).update_all(used_at: Time.current) == 1
  end

  def revoke_token(claims)
    McpToken.where(token_id: claims[:id]).update_all(revoked_at: Time.current)
  end
end
```

A used refresh token's row is marked used, so the grant doesn't need `refresh_token_id`.

Delete expired rows from time to time, for example with `McpToken.where(expires_at: ...1.day.ago).delete_all` in a recurring job. Expired rows are never read again. Without the cleanup job, the table grows with every sign-in and refresh.
