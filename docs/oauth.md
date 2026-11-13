# How the OAuth gem works

MCP clients, such as Claude, sign people in with OAuth. `stateless-mcp-oauth` will let an app act as the OAuth server for them, using the app's sign-in and consent pages.

> **Not released yet.** Every step of a sign-in is built and tested end to end.

## A sign-in

1. **The client finds the app's OAuth server** from the MCP server's metadata. The client's ID is the URL of its metadata document, so the client doesn't need to register first.
2. **The person signs in to the app and approves the client** on the app's consent page. That approval is a *grant*: one person allowing one client to use one MCP server.
3. **The app gives the client an authorization code.** The client exchanges the authorization code for an access token and a refresh token. PKCE proves it's the same client that started the sign-in. An authorization code works once. If it's exchanged again, it may have been stolen, so the gem revokes the grant it made.
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

### Rack and Sinatra

`StatelessMcp::OAuth::RequireToken` goes before `StatelessMcp::Middleware`, with the same server:

```ruby
# config.ru
use StatelessMcp::OAuth::RequireToken, protected_resource: MCP_OAUTH, server: SERVER
use StatelessMcp::Middleware, server: SERVER
run NotesMcp.new
```

- **It checks the same requests** that `StatelessMcp::Middleware` handles, using the server's own endpoint check.
- **A request with a valid token** reaches the app with its grant in `env["stateless_mcp.oauth.grant"]`.
- **It serves the metadata** at `MCP_OAUTH.metadata_path`.
- **Other requests pass through.**

A Sinatra app adds the same `use` line above its `use StatelessMcp::Middleware`.

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

### The consent page

The app serves the consent page at the OAuth server's `authorization_path`. The person signs in to the app as usual. The page shows which client is asking for access, and the person approves or denies it.

`MCP_OAUTH_SERVER.authorization_request(params)` checks the client's request, in the order RFC 6749 sets:

- **If the client or redirect URI can't be trusted,** `authorization_request` raises a `StatelessMcp::OAuth::Error`. The app shows the error message to the person, and doesn't redirect.
- **Any other problem,** such as a missing PKCE challenge or an unknown scope, is returned by `problem`. `error_redirect_url` returns the URL that reports it to the client.
- **On approval,** `approve(user_id: current_user.id)` issues the authorization code through the MCP server's storage. It returns the URL that sends the person back to the client with the authorization code. Its keyword arguments become `approved_by`, which `create_grant` gets when the authorization code is exchanged.
- **On denial,** `deny` returns the URL to send the person back with `access_denied`.

Nothing is stored until `approve`, so showing the page on a GET is safe. In Rails:

```ruby
# app/controllers/mcp_authorizations_controller.rb
class McpAuthorizationsController < ApplicationController
  before_action :authenticate_user! # the app's sign-in
  before_action :load_authorization

  def new
  end

  def create
    url = params[:decision] == "approve" ? @authorization.approve(user_id: current_user.id) : @authorization.deny
    redirect_to url, allow_other_host: true
  end

  private
    # If the client or redirect URI can't be trusted, show the error to the
    # person and don't redirect. Send any other problem to the client.
    def load_authorization
      @authorization = MCP_OAUTH_SERVER.authorization_request(params)
      redirect_to @authorization.error_redirect_url, allow_other_host: true if @authorization.problem
    rescue StatelessMcp::OAuth::Error => error
      render plain: error.message, status: :bad_request
    end
end
```

```erb
<%# app/views/mcp_authorizations/new.html.erb %>
<% client = @authorization.client %>
<h1>Allow <%= client.name %> to use your notes?</h1>

<p>
  It's from <strong><%= client.host %></strong>.
  Allowing it sends you back to <strong><%= @authorization.redirect_host %></strong>.
</p>

<% if @authorization.loopback_redirect? %>
  <p>That's an app on this computer. Only allow it if you just started connecting an app you trust.</p>
<% end %>

<% if @authorization.scopes.any? %>
  <p>It asks for: <%= @authorization.scopes.to_sentence %>.</p>
<% end %>

<%= form_with url: request.path, method: :post do |form| %>
  <% @authorization.params.each do |name, value| %>
    <%= hidden_field_tag name, value, id: nil %>
  <% end %>
  <%= form.button "Allow", name: "decision", value: "approve" %>
  <%= form.button "Deny", name: "decision", value: "deny" %>
<% end %>
```

```ruby
# config/routes.rb, inside Rails.application.routes.draw
get MCP_OAUTH_SERVER.authorization_path, to: "mcp_authorizations#new"
post MCP_OAUTH_SERVER.authorization_path, to: "mcp_authorizations#create"
```

- **The page should show where the person goes back to,** because that's where the authorization code is sent. `loopback_redirect?` is true when the redirect URI points to an app on the person's computer.
- **The form posts the request's params back** with the app's CSRF token, so the approval can't come from another site.
- **The consent page mustn't be shown in a frame,** or another site could trick the person into clicking Allow. Rails sends `X-Frame-Options: SAMEORIGIN` by default. A Rack or Sinatra app sends `Content-Security-Policy: frame-ancestors 'none'` on the consent page itself.
- **A client that asks for no scope** gets the MCP server's `default_scopes`, which are none unless the app lists some, such as `default_scopes: ["notes:read"]` beside `scopes:`. With none, the request has an `invalid_scope` problem.

A Rack or Sinatra app calls the same methods from its routes.

### The token endpoint

At the token endpoint, a client exchanges an authorization code for an access token and a refresh token. Later, it exchanges the refresh token for new tokens. In Rails:

```ruby
# config/routes.rb, inside Rails.application.routes.draw
post MCP_OAUTH_SERVER.token_path, to: MCP_OAUTH_SERVER.token_app
```

In a Rack or Sinatra app:

```ruby
# config.ru
map(MCP_OAUTH_SERVER.token_path) { run MCP_OAUTH_SERVER.token_app }
```

- **Exchanging an authorization code** needs the PKCE code verifier, client ID and redirect URI from its authorization request. The storage's `create_grant` is called only after those checks pass, so someone without the code verifier can't use up another client's authorization code.
- **Refreshing** consumes the used refresh token before issuing new ones. If a client sends a refresh token that was already used, the token must have been copied, and the grant is revoked.
- **Tokens last** two minutes for an authorization code, an hour for an access token and 30 days for a refresh token. Pass `code_ttl:`, `access_token_ttl:` or `refresh_token_ttl:` to change them.
- **Clients are public,** with no secret. A request with a secret or an `Authorization` header gets a 401.

## What the app provides

- **Storage:** a subclass of `StatelessMcp::OAuth::Storage`, storing grants and tokens however the app chooses. See [OAuth storage](oauth-storage.md).
- **Sign-in and consent pages,** in the app's style. The gem checks the authorization request, and issues the authorization code on approval.
- **A check before each MCP request,** as [above](#checking-mcp-requests).

## What the gem provides

- **Request checks:** `verified_grant`, the 401's headers, the metadata and `RequireToken`.
- **The OAuth server's metadata, and client checks:** fetching each client's metadata document safely, and checking it.
- **The authorization request:** its checks, the authorization code on approval, and the redirects back to the client.
- **The token endpoint:** exchanging authorization codes with PKCE, and refreshing tokens. Reusing a refresh token revokes its grant.
- **The order of storage calls,** so a token can't be used twice, even if a call fails.
- **`StorageCheck`,** which tests the app's storage class from Minitest or RSpec.

The app controls the database and the encryption, so OAuth state sits beside its users, and tokens use libraries the app already maintains.
