# How the OAuth gem works

MCP clients, such as Claude, sign people in with OAuth. `stateless-mcp-oauth` will let an app act as the OAuth server for them, using the app's sign-in and consent pages.

> **In progress.** Storage, request checks, the OAuth server's metadata and client checks exist. The consent page helpers and the token endpoint are still to come, so nothing issues tokens yet, and the gem isn't released.

## A sign-in

1. **The client finds the app's OAuth server** from the MCP server's metadata. The client's ID is the URL of its metadata document, so the client doesn't need to register first.
2. **The person signs in to the app and approves the client** on the app's consent page. That approval is a *grant*: one person allowing one client to use one MCP server.
3. **The app gives the client an authorization code.** The client exchanges the authorization code for an access token and a refresh token. PKCE proves it's the same client that started the sign-in.
4. **The client sends the access token with each MCP request.** The app's `before_action` or middleware uses the gem to find the token's grant, and reads who approved from it.
5. **When the access token expires,** the client exchanges its refresh token for a new access token and refresh token. Each refresh token works once. If a used refresh token is sent again, it must have been copied, so the gem revokes the grant.

## Checking MCP requests

The app makes one `StatelessMcp::OAuth::ProtectedResource`. OAuth calls a server whose requests need a token a *protected resource*, and here that's the MCP server:

```ruby
# config/initializers/mcp_oauth.rb
MCP_OAUTH = StatelessMcp::OAuth::ProtectedResource.new(
  resource: "https://notes.example/mcp",
  authorization_server: "https://notes.example",
  storage: McpOAuthStorage.new
)
```

- **`resource`** is the MCP server's URL. A token only works for the server it was issued for.
- **`authorization_server`** is the URL of the app's OAuth server, where clients sign people in.
- **`storage`** is the app's [storage class](oauth-storage.md).

`MCP_OAUTH.verified_grant(request)` returns the grant behind a request's access token, from the storage's `find_grant`. It returns `nil` when there's no token, or when the token is unknown, revoked, expired, not an access token, or for another MCP server. The grant says who approved, with whatever attributes the app chose, such as `user_id`.

A request without a valid token gets a 401. Its `WWW-Authenticate` header, from `MCP_OAUTH.unauthorized_headers`, points the client at the server's metadata. The metadata names the OAuth server, where the client then signs the person in.

### Rails

A `before_action` in the tools' base controller checks each request:

```ruby
# app/controllers/mcp/base_controller.rb
class Mcp::BaseController < ActionController::API
  include StatelessMcp::Rails::Controller

  before_action :require_mcp_token

  private
    # The grant says who approved, such as @mcp_grant.user_id.
    def require_mcp_token
      @mcp_grant = MCP_OAUTH.verified_grant(request)
      head :unauthorized, MCP_OAUTH.unauthorized_headers(invalid_token: request.authorization.present?) unless @mcp_grant
    end
end
```

**The protected resource metadata** (RFC 9728) is how a client finds where to sign in. It names the app's OAuth server, the scopes, and how to send a token. A client reads it from a well-known URL after its first 401, so it needs a route:

```ruby
# config/routes.rb, inside Rails.application.routes.draw
get MCP_OAUTH.metadata_path, to: MCP_OAUTH.metadata_app
```

## The OAuth server

The app makes one `StatelessMcp::OAuth::AuthorizationServer`, for the MCP servers it protects:

```ruby
# config/initializers/mcp_oauth.rb, after MCP_OAUTH
MCP_OAUTH_SERVER = StatelessMcp::OAuth::AuthorizationServer.new(
  issuer: "https://notes.example",
  protected_resources: [MCP_OAUTH]
)
```

The OAuth server's metadata (RFC 8414) lists where clients sign people in and where they get tokens. In Rails, it's served from a route:

```ruby
# config/routes.rb, inside Rails.application.routes.draw
get MCP_OAUTH_SERVER.metadata_path, to: MCP_OAUTH_SERVER.metadata_app
```

A Rack or Sinatra app serves the metadata with a `map`:

```ruby
# config.ru
map(MCP_OAUTH_SERVER.metadata_path) { run MCP_OAUTH_SERVER.metadata_app }
```

### MCP clients

MCP clients don't register with the OAuth server. Instead, a client's client ID is the URL of its client metadata document. That document is a JSON file the client publishes, listing its name and redirect URIs. `MCP_OAUTH_SERVER.client(client_id)` fetches the document, checks it and returns it.

- **The fetch is limited,** because the client chooses the URL. The URL must be https and resolve to a public IP address. The response must be served as `application/json`, and can't redirect or be compressed. It must be at most 5 KB and arrive within a few seconds.
- **The checks:** the document must contain the same client ID as its URL, and a client name. Each redirect URI must be https, or http to a loopback address, for an app on the person's computer. The port of a loopback redirect URI can change, since the app listens on whichever port is free. The document must describe a public client, one with no client secret, that uses the authorization code flow.
- **The ssrf_filter gem** checks the IP address before each fetch, and the connection goes to the address it checked. Add `gem "ssrf_filter"` to the app's Gemfile.
- **`localhost` counts as a loopback address** by default, since Claude Code and Cursor redirect to it. RFC 8252 advises only `127.0.0.1` and `[::1]`, since a name can resolve elsewhere. Pass `localhost_redirects: false` to accept only those, which refuses a client whose document lists `http://localhost`.
- **In production, send the fetch through an egress proxy,** such as Smokescreen, so the network refuses internal addresses too, and the fetch comes from the proxy's address rather than the app's:

```ruby
# config/initializers/mcp_oauth.rb, in place of the MCP_OAUTH_SERVER above
MCP_OAUTH_SERVER = StatelessMcp::OAuth::AuthorizationServer.new(
  issuer: "https://notes.example",
  protected_resources: [MCP_OAUTH],
  client_metadata_transport: StatelessMcp::OAuth::DocumentTransport.new(proxy: ENV.fetch("EGRESS_PROXY_URL"))
)
```

  The proxy resolves the host and makes the connection, so ssrf_filter's checks no longer apply. The proxy must refuse internal addresses itself. The gem's other rules still do: https only, no redirects, a 200 served as JSON, uncompressed, within 5 KB and a few seconds.
- **Documents are cached** for as long as their `Cache-Control` header allows, between a minute and a day. By default the cache is in the Ruby process's memory. Pass `client_metadata_cache: Rails.cache` to share it between processes.

## What the app provides

- **Storage:** a subclass of `StatelessMcp::OAuth::Storage`, storing grants and tokens however the app chooses. See [OAuth storage](oauth-storage.md).
- **Sign-in and consent pages,** in the app's style.
- **A check before each MCP request,** as [above](#checking-mcp-requests).

## What the gem provides

- **Request checks:** `verified_grant`, the 401's headers and the metadata.
- **The OAuth server's metadata, and client checks:** fetching each client's metadata document safely, and checking it.
- **The OAuth endpoints and their checks:** PKCE, redirect URIs, scopes and expiry. These are still to come.
- **The order of storage calls,** so a token can't be used twice, even if a call fails.
- **`StorageCheck`,** which tests the app's storage class from Minitest or RSpec.

The app controls the database and the encryption, so OAuth state sits beside its users, and tokens use libraries the app already maintains.
