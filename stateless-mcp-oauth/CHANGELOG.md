# Changelog

Changes to the `stateless-mcp-oauth` gem, released at the same version as [`stateless-mcp`](../stateless-mcp/CHANGELOG.md). The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

- `StatelessMcp::OAuth::Storage`, the class an app subclasses to keep grants and tokens however it chooses. Tested examples encrypt tokens with Rails' `MessageEncryptor`, or keep them as rows.
- `StatelessMcp::OAuth::ProtectedResource`, which checks each MCP request's access token and returns its grant. A 401 points the client at the server's metadata, which a browser-based client can read from any origin. `StatelessMcp::OAuth::RequireToken` does the same as Rack middleware, for Rack and Sinatra apps. `verified_grant!` raises `InvalidToken` with the reason a token was refused, for the app's logs.
- `StatelessMcp::OAuth::AuthorizationServer`, which serves the OAuth server's metadata (RFC 8414). It also fetches and checks each MCP client's metadata document, so clients don't need to register.
- `StatelessMcp::OAuth::AuthorizationRequest`, which checks a client's authorization request. When the person approves on the app's consent page, it issues the authorization code and returns the client's redirect URL. A client that asks for no scope gets the MCP server's `default_scopes`, none unless the app lists some.
- The token endpoint, which exchanges authorization codes with PKCE and refreshes tokens. When an authorization code or a refresh token is used twice, its grant is revoked, through the storage's optional `revoke_grant_for_code` for a code.
- `StatelessMcp::OAuth::StorageCheck`, in `test_support`, which checks an app's storage class from Minitest or RSpec, including race conditions.
- Guides to OAuth, to storage, and to moving storage, including from Doorkeeper.

[Unreleased]: https://github.com/Jamedjo/stateless-mcp/compare/v0.0.1...HEAD
