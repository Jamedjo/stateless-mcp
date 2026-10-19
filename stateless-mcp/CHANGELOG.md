# Changelog

Changes to the `stateless-mcp` gem. The Rails integration has [its own changelog](../stateless-mcp-rails/CHANGELOG.md). The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.0.1] - 2026-10-19

First release: a Rack endpoint for the stateless MCP protocol, 2026-07-28.

- `StatelessMcp::Server`: one endpoint's settings, validated, with a default for each.
- `StatelessMcp::Middleware`: reads the JSON-RPC body within the server's limit, checks `Origin`, and refuses requests whose headers disagree with the body.
- JSON-RPC errors with the HTTP status the spec gives each.
- `StatelessMcp::ToolDeclaration`, `StatelessMcp::Result` and `StatelessMcp::Pagination`: tool listings, results, and cursor paging of lists and long text.
- Guides and examples for plain Rack and Sinatra.

[Unreleased]: https://github.com/Jamedjo/stateless-mcp/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/Jamedjo/stateless-mcp/tree/v0.0.1/stateless-mcp
