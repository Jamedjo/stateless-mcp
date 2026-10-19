# Moving OAuth storage

This page covers moving an app's [OAuth storage](oauth-storage.md) from one design to another, without signing anyone out. Like the examples on that page, these are tested ActiveRecord examples, not designs the gem requires.

## Example: from encrypted tokens to token rows

1. Add the `mcp_tokens` table and the `McpToken` model from [the token rows example](oauth-storage.md#example-token-rows).
2. In the storage class, rename `read_token` to `read_encrypted_token` and `consume_refresh_token` to `consume_encrypted_refresh_token`.
3. Add `issue_token` from the token rows example, and remove `issue_tokens`. Then replace `read_token`, `consume_refresh_token` and `revoke_token` with these:

```ruby
# app/models/mcp_oauth_storage.rb
class McpOAuthStorage < StatelessMcp::OAuth::Storage
  # New tokens are stored as rows. Encrypted ones keep working until they
  # expire or are refreshed.
  def read_token(token)
    McpToken.find_by(digest: McpToken.digest(token), revoked_at: nil)&.claims || read_encrypted_token(token)
  end

  def consume_refresh_token(claims)
    return consume_encrypted_refresh_token(claims) unless McpToken.exists?(token_id: claims[:id])
    McpToken.where(token_id: claims[:id], used_at: nil, revoked_at: nil).update_all(used_at: Time.current) == 1
  end

  # An encrypted token has no row, so its grant is revoked instead.
  def revoke_token(claims)
    super if McpToken.where(token_id: claims[:id]).update_all(revoked_at: Time.current).zero?
  end
end
```

The next time an encrypted refresh token is used, its replacement is stored as a row. Once no grant has a `refresh_token_id`, the encrypted methods and the key can be removed.

Moving from token rows to encrypted tokens works the same way, with the two designs swapped.

## Example: from Doorkeeper

Clients signed in through Doorkeeper carry on without signing in again. Their tokens keep working until each is refreshed. New tokens go in the app's own tables, and Doorkeeper's tables aren't changed.

1. **Start from [the token rows example](oauth-storage.md#example-token-rows).** New tokens are stored as its rows.
2. **Read Doorkeeper's tokens** when a token isn't one of the app's rows. The first time a token for an application and person turns up, this creates a grant for that pair:

```ruby
# app/models/mcp_oauth_storage.rb
class McpOAuthStorage < StatelessMcp::OAuth::Storage
  def read_token(token)
    McpToken.find_by(digest: McpToken.digest(token), revoked_at: nil)&.claims || doorkeeper_claims(token)
  end

  private
    def doorkeeper_claims(token)
      if (row = Doorkeeper::AccessToken.by_token(token))
        doorkeeper_claims_for(row, kind: "access", expires_at: row.expires_at) unless row.revoked?
      elsif (row = Doorkeeper::AccessToken.by_refresh_token(token))
        doorkeeper_claims_for(row, kind: "refresh", expires_at: row.created_at + 30.days)
      end
    end

    # One grant per application and person, made the first time it's seen.
    def doorkeeper_claims_for(row, kind:, expires_at:)
      grant_id = "doorkeeper-#{row.application_id}-#{row.resource_owner_id}"
      create_grant(code_id: grant_id,
                   authorization_request: { client_id: row.application.uid, resource: "https://notes.example/mcp", scope: row.scopes.to_s },
                   approved_by: { user_id: row.resource_owner_id })
      { kind:, id: "doorkeeper-#{kind}-#{row.id}", grant_id:, expires_at: expires_at.to_i, doorkeeper_id: row.id }
    end
end
```

3. **Use up and revoke Doorkeeper's tokens.** The claims for a Doorkeeper token include `doorkeeper_id`, a key the storage adds, so these methods know which table to update:

```ruby
# app/models/mcp_oauth_storage.rb
class McpOAuthStorage < StatelessMcp::OAuth::Storage
  def consume_refresh_token(claims)
    if claims[:doorkeeper_id]
      Doorkeeper::AccessToken.where(id: claims[:doorkeeper_id], revoked_at: nil).update_all(revoked_at: Time.current) == 1
    else
      McpToken.where(token_id: claims[:id], used_at: nil, revoked_at: nil).update_all(used_at: Time.current) == 1
    end
  end

  def revoke_token(claims)
    if claims[:doorkeeper_id]
      Doorkeeper::AccessToken.where(id: claims[:doorkeeper_id]).update_all(revoked_at: Time.current)
    else
      McpToken.where(token_id: claims[:id]).update_all(revoked_at: Time.current)
    end
  end
end
```

Replace `https://notes.example/mcp` with the URL of the app's MCP server.

### Notes

- **Doorkeeper's refresh tokens don't expire,** so the example treats them as lasting 30 days from when they were issued.
- **A used Doorkeeper refresh token still reads,** so the gem can catch it being used again.
- **Hashed tokens work too.** `by_token` and `by_refresh_token` handle Doorkeeper's `hash_token_secrets`.
- **Two sign-ins share a grant** when the same person signs in to the same client twice, so revoking it ends both. Doorkeeper's authorized applications page works the same way.
- **The example is tested** against the `doorkeeper` gem, with `gemfiles/doorkeeper.gemfile`.

### How Doorkeeper's tables map

| | Doorkeeper stores it in | Storage methods |
|---|---|---|
| A grant: one person allowing one client | No table. Doorkeeper works out its "authorized applications" from live access tokens. | `create_grant`, `find_grant`, `revoke_grant` |
| Authorization code: the short-lived, single-use value a client exchanges for its first tokens | `oauth_access_grants` | `issue_token`, `read_token` |
| Access token | `oauth_access_tokens` | `issue_token`, `read_token` |
| Refresh token | The `refresh_token` column of its access token's row | `issue_token`, `read_token`, `consume_refresh_token` |

Doorkeeper calls an authorization code a grant, as OAuth's original spec does. In this gem, a grant is the person's approval, which Doorkeeper has no row for.
