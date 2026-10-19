# Changelog

Changes to the `stateless-mcp-oauth` gem, released at the same version as [`stateless-mcp`](../stateless-mcp/CHANGELOG.md). The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

- `StatelessMcp::OAuth::Storage`, the class an app subclasses to keep grants and tokens however it chooses. Tested examples encrypt tokens with Rails' `MessageEncryptor`, or keep them as rows.
- `StatelessMcp::OAuth::StorageCheck`, in `test_support`, which checks an app's storage class from Minitest or RSpec, including race conditions.
- Guides to OAuth, to storage, and to moving storage, including from Doorkeeper.

[Unreleased]: https://github.com/Jamedjo/stateless-mcp/compare/v0.0.1...HEAD
