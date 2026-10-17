# Changelog

Both gems share one version and one changelog. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `stateless-mcp` and `stateless-mcp-rails` gems, locked to the same version.
- `StatelessMcp::Server`: one endpoint's settings, validated, with a default for each.
- `StatelessMcp::Middleware`: reads a server's JSON-RPC body within its limit and refuses requests whose 2026-07-28 headers disagree with it.
- JSON-RPC errors with the status the spec gives each, and opaque cursors.
- `StatelessMcp::ToolDeclaration`: a tool's `tools/list` entry and argument schema, with paging described by each server's own page sizes.
- `StatelessMcp::Result` and `StatelessMcp::Pagination`: results in the shapes 2026-07-28 expects, and cursor paging of lists and long text within a server's page sizes.
