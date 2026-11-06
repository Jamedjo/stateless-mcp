# stateless-mcp-oauth

OAuth for [stateless-mcp](https://github.com/Jamedjo/stateless-mcp) servers. Storage is customizable. A subclass of `StatelessMcp::OAuth::Storage` reads and writes OAuth state in the app's tables.

```ruby
gem "stateless-mcp-oauth"
```

Not released yet. Every step of a sign-in is built and tested end to end. [How the OAuth gem works](https://github.com/Jamedjo/stateless-mcp/blob/main/docs/oauth.md) covers the sign-in. [OAuth storage](https://github.com/Jamedjo/stateless-mcp/blob/main/docs/oauth-storage.md) covers the storage class, which keeps grants and tokens however the app chooses, with tested examples.

Licensed under either of Apache-2.0 or MIT, at your option.
