# How the OAuth gem works

MCP clients, such as Claude, sign people in with OAuth. `stateless-mcp-oauth` will let an app act as the OAuth server for them, using the app's sign-in and consent pages.

> **In progress.** Only storage exists so far. The token endpoint, consent helpers and request checks described below are still to come, and the gem isn't released yet.

## A sign-in

1. **The client finds the app's OAuth server** from the MCP server's metadata. The client's ID is the URL of its metadata document, so the client doesn't need to register first.
2. **The person signs in to the app and approves the client** on the app's consent page. That approval is a *grant*: one person allowing one client to use one MCP server.
3. **The app gives the client an authorization code.** The client exchanges the authorization code for an access token and a refresh token. PKCE proves it's the same client that started the sign-in.
4. **The client sends the access token with each MCP request.** The app's `before_action` or middleware uses the gem to find the token's grant, and reads who approved from it.
5. **When the access token expires,** the client exchanges its refresh token for a new access token and refresh token. Each refresh token works once. If a used refresh token is sent again, it must have been copied, so the gem revokes the grant.

## What the app provides

- **Storage:** a subclass of `StatelessMcp::OAuth::Storage`, storing grants and tokens however the app chooses. See [OAuth storage](oauth-storage.md).
- **Sign-in and consent pages,** in the app's style.
- **A check before each MCP request,** in the same place as any other [authentication](../README.md#authentication).

## What the gem provides

- **The OAuth endpoints and their checks:** PKCE, redirect URIs, scopes and expiry.
- **The order of storage calls,** so a token can't be used twice, even if a call fails.
- **`StorageCheck`,** which tests the app's storage class from Minitest or RSpec.

The app controls the database and the encryption, so OAuth state sits beside its users, and tokens use libraries the app already maintains.
