# Changelog

Changes to the `stateless-mcp-rails` gem. It's released at the same version as `stateless-mcp`, whose [changelog](../stateless-mcp/CHANGELOG.md) covers the protocol. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.0.1] - 2026-10-19

First release: MCP servers declared in Rails routes, with tools as controller actions.

- An engine building a default server from `config.stateless_mcp`, and the `mcp_server`, `mcp_resource`, `mcp_member` and `mcp_tool` route macros.
- `server/discover` and `tools/list` answered from config and routes, each server listing only its own tools.
- Tool calls: arguments checked against the declared schema and read through `tool_params`, refusals the model can act on, and internal errors reported to `Rails.error`.
- `paginate_list` and `paginate_text`, plus keyset paging for ActiveRecord from `require "stateless_mcp/rails/active_record"`.
- `rake mcp:tools`, listing each server's tools.
- Boot refused until `parent_controller` names the app's own base controller, or `allow_unauthenticated` is `true`.

[Unreleased]: https://github.com/Jamedjo/stateless-mcp/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/Jamedjo/stateless-mcp/tree/v0.0.1/stateless-mcp-rails
