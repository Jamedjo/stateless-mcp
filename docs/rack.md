# Plain Rack

This guide uses the `stateless-mcp` gem in a Rack app with no framework. The gem provides the middleware and building blocks; the app defines the tools and handles each MCP method itself.

- [Full example](#full-example)
- [Trying it with curl](#trying-it-with-curl)
- [Server settings](#server-settings)
- [What the middleware checks](#what-the-middleware-checks)
- [Building blocks](#building-blocks)
- [Declaring arguments](#declaring-arguments)
- [Authentication](#authentication)
- [Several servers](#several-servers)
- [Testing](#testing)

## Full example

This `config.ru` serves one tool, `get_note`, at `/mcp`. It is [`examples/rack/config.ru`](../examples/rack/config.ru), and CI runs it:

```ruby
require "stateless-mcp"

NOTES = { 1 => "Buy milk", 2 => "Call the plumber" }.freeze

SERVER = StatelessMcp::Server.new(name: "notes")

GET_NOTE = StatelessMcp::ToolDeclaration.new(title: "Get a note", description: "Gets one note by its id.") do
  argument :note_id, :integer, "The note's id", required: true
end

# Called only for requests the middleware has checked, with the parsed body in the env.
class NotesMcp
  def call(env)
    rpc = env[StatelessMcp::REQUEST_ENV_KEY] or return [404, {}, []]
    return [202, {}, []] unless rpc.key?("id") # Notifications have no response.

    case rpc["method"]
    when "server/discover" then success(rpc, StatelessMcp::Result.discover(SERVER, capabilities: { tools: {} }))
    when "tools/list" then success(rpc, StatelessMcp::Result.complete({ tools: [GET_NOTE.to_h("get_note", SERVER)] }, cacheable: true))
    when "tools/call" then call_tool(rpc)
    else error(rpc, StatelessMcp::Rpc::ErrorCode::METHOD_NOT_FOUND, "Method not found")
    end
  end

  private

  def call_tool(rpc)
    name, arguments = rpc["params"].values_at("name", "arguments")
    return error(rpc, StatelessMcp::Rpc::ErrorCode::INVALID_PARAMS, "Unknown tool: #{name}") unless name == "get_note"

    GET_NOTE.input_schema(SERVER).validate_arguments(arguments || {})
    note = NOTES[arguments["note_id"]]
    success(rpc, note ? StatelessMcp::Result.tool(id: arguments["note_id"], text: note) : StatelessMcp::Result.refusal("No note #{arguments["note_id"]}"))
  rescue MCP::Tool::InputSchema::ValidationError => invalid
    success(rpc, StatelessMcp::Result.refusal(invalid.message))
  end

  def success(rpc, result)
    json(200, StatelessMcp::Rpc.success(rpc["id"], result))
  end

  def error(rpc, code, message)
    json(StatelessMcp::Rpc.status_for(code), StatelessMcp::Rpc.error(rpc["id"], code, message))
  end

  def json(status, body)
    [status, { "content-type" => "application/json" }, [JSON.generate(body)]]
  end
end

use StatelessMcp::Middleware, server: SERVER
run NotesMcp.new
```

The app handles four cases:

- `server/discover` and `tools/list`, with results from `StatelessMcp::Result`;
- `tools/call`, which checks the arguments against the tool's schema and returns a result or a tool error;
- notifications, with an empty 202;
- any other method, with a JSON-RPC error and a 404.

## Trying it with curl

Start the example with `bundle exec rackup` in `examples/rack`, then list its tools:

```sh
curl -s localhost:9292/mcp \
  -H 'Content-Type: application/json' \
  -H 'MCP-Protocol-Version: 2026-07-28' \
  -H 'Mcp-Method: tools/list' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'
```

## Server settings

A `StatelessMcp::Server` describes one MCP endpoint: its path, its name and its limits.

```ruby
SERVER = StatelessMcp::Server.new(path: "/mcp", name: "notes", version: "1.2.0")
```

`StatelessMcp::Server.new` accepts these settings, each with a default:

| Setting | Default | Meaning |
|---|---|---|
| `path` | `"/mcp"` | The endpoint's absolute path |
| `name`, `version`, `title` | `"mcp"`, `"1.0.0"`, none | The `serverInfo` that clients show |
| `instructions` | none | Guidance for the model on using the server as a whole |
| `max_body_bytes` | 1 MB | The largest request body accepted |
| `check_origin` | `true` | Whether to check the `Origin` header |
| `allowed_origins` | none | Other origins allowed to call the server, such as `"https://app.example"` |
| `page_size` | 20 | Page size when a call asks for none |
| `max_page_size` | 100 | The largest page a call may ask for |
| `tool_verbs` | `index: "list", show: "get", …` | Tool names for Rails resource actions. Merged over the defaults |

An invalid setting raises `StatelessMcp::Server::Invalid`, an `ArgumentError` that names the setting. A server is frozen once built, so it is safe to share between threads.

## What the middleware checks

`StatelessMcp::Middleware` handles requests to its server's path, and passes every other request to the app unchanged. For the server's path, it applies these steps in order:

1. A request from another site's page, by its `Origin` header, gets a 403. See [The Origin check](../README.md#the-origin-check).
2. GET and DELETE get a 405. Earlier protocol revisions use them for streams and sessions.
3. A POST body must be at most `max_body_bytes`, and one JSON-RPC request.
4. The `MCP-Protocol-Version`, `Mcp-Method` and `Mcp-Name` headers must match the body, as the [Streamable HTTP transport](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http#server-validation) requires, and the body must have a valid `_meta` envelope.

A request that fails a check gets a JSON-RPC error, with the HTTP status from the spec:

| Problem | Code | Status |
|---|---|---|
| Body too large, or not one request | `-32600` | 400 |
| Body isn't JSON | `-32700` | 400 |
| A header missing or different from the body | `-32020` | 400 |
| A protocol version the server doesn't support | `-32022`, with the supported versions | 400 |
| `_meta` envelope missing or malformed | `-32602` | 400 |

After the checks, the app's Rack env has:

- the server in `env[StatelessMcp::Server::ENV_KEY]`;
- the parsed body in `env[StatelessMcp::REQUEST_ENV_KEY]`;
- the body as a fresh `rack.input`, for apps that parse it again;
- the `Mcp-Name` header decoded, if the client sent it base64 encoded.

## Building blocks

The app builds its responses with these:

| Building block | Use |
|---|---|
| `StatelessMcp::Rpc.success(id, result)`, `.error(id, code, message, data:)` | JSON-RPC response bodies, from the `mcp` gem |
| `StatelessMcp::Rpc.status_for(code)` | The HTTP status for a JSON-RPC error: 404 for an unknown method, 400 for a malformed request, otherwise 200 |
| `StatelessMcp::ToolDeclaration.new(title:, description:) { … }` | A tool's `tools/list` entry, from `#to_h(name, server)`, and its argument schema, from `#input_schema(server)` |
| `StatelessMcp::Result.discover(server, capabilities:)` | The result for `server/discover` |
| `StatelessMcp::Result.complete(result, cacheable:)` | Any other result, with the `resultType` field that 2026-07-28 requires, and cache hints when `cacheable` is true |
| `StatelessMcp::Result.tool(payload)` | A tool result, as JSON in one text block |
| `StatelessMcp::Result.refusal(message)` | A tool error with a message for the model |
| `StatelessMcp::Pagination.limit`, `.list`, `.text` | Paging a list or a long text by position, within the server's page sizes |
| `StatelessMcp::Cursor.encode(*values)`, `.decode(cursor, count:)` | Opaque, URL-safe cursors. `decode` raises `StatelessMcp::Cursor::Invalid` for a cursor this gem didn't create |

## Declaring arguments

A `ToolDeclaration` block lists the tool's arguments:

```ruby
LIST_NOTES = StatelessMcp::ToolDeclaration.new(title: "List notes", description: "Lists notes, newest first.") do
  argument :tag, :string, "Only notes with this tag"
  argument :created_after, :datetime, "ISO 8601 date or time"
  paginated "notes"
end
```

The block accepts these two methods:

| Method | Use |
|---|---|
| `argument name, type, description, required:, **keywords` | One argument. Types are JSON Schema types, plus `:datetime`, sent as a string. Keywords such as `enum:` are added to the schema unchanged |
| `paginated noun` | Adds `limit` and `cursor` arguments, described with the server's page sizes |

A declared tool is marked read-only unless `annotations:` is given.

To check a call's arguments, pass them to `input_schema(server).validate_arguments`. It raises `MCP::Tool::InputSchema::ValidationError` with a message for the model, as the full example shows.

## Authentication

The gem has no authentication. Until the app adds a check, anyone who can reach the endpoint can call every tool.

Add the check as Rack middleware, listed before `StatelessMcp::Middleware`. Rack runs middleware in order, so a request without the token gets a 401 before its body is parsed:

```ruby
# Returns 401 unless the Authorization header has the shared token.
class RequireToken
  def initialize(app, token:)
    @app = app
    @token = token
  end

  def call(env)
    return [401, { "www-authenticate" => "Bearer" }, []] unless Rack::Utils.secure_compare(env["HTTP_AUTHORIZATION"].to_s, "Bearer #{@token}")
    @app.call(env)
  end
end

use RequireToken, token: ENV.fetch("MCP_TOKEN")
use StatelessMcp::Middleware, server: SERVER
```

## Several servers

Use one middleware per server. Each middleware handles only its own server's path, with that server's limits:

```ruby
notes = StatelessMcp::Server.new(path: "/mcp", name: "notes")
admin = StatelessMcp::Server.new(path: "/admin/mcp", name: "admin", max_body_bytes: 16_384)

use StatelessMcp::Middleware, server: notes
use StatelessMcp::Middleware, server: admin
run MyApp
```

The app reads `env[StatelessMcp::Server::ENV_KEY]` to find the server for a request.

## Testing

A test sends requests in the same form as a client. Each POST needs:

- the headers `Content-Type: application/json`, `MCP-Protocol-Version: 2026-07-28` and `Mcp-Method`, plus `Mcp-Name` with the tool's name for `tools/call`;
- a `_meta` object in `params` with `io.modelcontextprotocol/protocolVersion` and `io.modelcontextprotocol/clientCapabilities`.

[`examples/smoke_check.rb`](../examples/smoke_check.rb) builds these requests with `Rack::MockRequest`, and runs them against both examples.
