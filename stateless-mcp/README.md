# stateless-mcp

The Rack side of [stateless-mcp](https://github.com/Jamedjo/stateless-mcp): serving the 2026-07-28 [Model Context Protocol](https://modelcontextprotocol.io/specification/2026-07-28) without sessions. Rails apps want [`stateless-mcp-rails`](../stateless-mcp-rails), which builds on this.

> **Status:** unreleased.

## A server

A `StatelessMcp::Server` is one MCP endpoint: where it is served, how it describes itself, and the limits it holds requests to. Every part of the library is handed the server it serves, so an app can run several.

```ruby
notes = StatelessMcp::Server.new(path: "/mcp", name: "notes", version: "1.2.0")
admin = StatelessMcp::Server.new(path: "/admin/mcp", name: "admin", max_body_bytes: 16_384)
```

| Setting | Default | |
|---|---|---|
| `path` | `"/mcp"` | The endpoint's absolute path |
| `name`, `version`, `title` | `"mcp"`, `"1.0.0"`, none | The `serverInfo` clients are shown |
| `instructions` | none | Guidance for the model on using the server as a whole |
| `max_body_bytes` | 1 MB | Larger bodies are refused before the rest is read |
| `page_size` | 20 | Page size when a call asks for none |
| `max_page_size` | 100 | The largest page a call may ask for |
| `tool_verbs` | `index: "list", show: "get", …` | How a resource's actions name its tools. Merged over the defaults |

A setting that can't be served raises `StatelessMcp::Server::Invalid`, an `ArgumentError` naming it. A server is frozen once built.

## The middleware

```ruby
# config.ru
use StatelessMcp::Middleware, server: notes
use StatelessMcp::Middleware, server: admin
run MyApp
```

Each middleware handles only its own server's path. A POST there is:

1. read within `max_body_bytes`, refusing an oversized body by its `Content-Length` or after reading one byte past the limit;
2. parsed as a single JSON-RPC request, refusing batches;
3. checked as the [Streamable HTTP transport](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http#server-validation) requires: `MCP-Protocol-Version`, `Mcp-Method` and `Mcp-Name` must be present and match the body, and the body must carry the `_meta` envelope.

A refused request is answered with a JSON-RPC error and the status the spec gives it:

| Problem | Code | Status |
|---|---|---|
| Body too large, or not one request | `-32600` | 400 |
| Body isn't JSON | `-32700` | 400 |
| A header missing or disagreeing with the body | `-32020` | 400 |
| A protocol version the server doesn't speak | `-32022`, with the supported versions | 400 |
| `_meta` envelope missing or malformed | `-32602` | 400 |

GET and DELETE, which earlier revisions use for streams and sessions, get `405 Method Not Allowed`.

A request that passes reaches the app with the server in `env[StatelessMcp::Server::ENV_KEY]` and the parsed body in `env[StatelessMcp::REQUEST_ENV_KEY]`. The body is put back as a fresh `rack.input`, so the app can parse it again as it would any other request. A base64-wrapped `Mcp-Name` is decoded in the env.

Authentication, rate limits and the `Origin` check are the app's, and middleware doing them goes before this one, so a request they refuse is never read.

## Building blocks

| | |
|---|---|
| `StatelessMcp::Rpc.success(id, result)`, `.error(id, code, message, data:)` | JSON-RPC envelopes, from the `mcp` gem |
| `StatelessMcp::Rpc.status_for(code)` | The HTTP status a JSON-RPC error travels with: 404 for an unknown method, 400 for a malformed request, otherwise 200 |
| `StatelessMcp::Cursor.encode(*values)`, `.decode(cursor, count:)` | Opaque, URL-safe cursors. Decoding one this library didn't issue raises `StatelessMcp::Cursor::Invalid` |
| `StatelessMcp::ToolDeclaration.new(title:, description:) { argument … }` | A tool's `tools/list` entry and its arguments' JSON Schema, built per server by `#to_h(name, server)` and `#input_schema(server)` |
| `StatelessMcp::Result.complete(result, cacheable:)`, `.discover(server, capabilities:)` | Results as 2026-07-28 shapes them: a `resultType`, and cache hints on cacheable ones |
| `StatelessMcp::Result.tool(payload)`, `.refusal(message)` | A tool's answer as JSON in one text block, and a refusal the model can read |
| `StatelessMcp::Pagination.limit`, `.list`, `.text` | Paging a list or a long text by position, held to a server's page sizes |
| `StatelessMcp::InvalidArgument` | Raised with a message the model can act on, and answered as a refused tool call |

## License

Licensed under either of Apache-2.0 or MIT, at your option.
