# Sinatra

There is no Sinatra-specific gem. A Sinatra app uses the `stateless-mcp` gem's middleware and building blocks, and handles the MCP methods in one route.

- [Full example](#full-example)
- [Authentication](#authentication)
- [Everything else](#everything-else)

## Full example

This app serves one tool, `get_note`, at `/mcp`. It is [`examples/sinatra`](../examples/sinatra), and CI runs it:

```ruby
require "sinatra/base"
require "stateless-mcp"

class NotesApp < Sinatra::Base
  NOTES = { 1 => "Buy milk", 2 => "Call the plumber" }.freeze

  SERVER = StatelessMcp::Server.new(name: "notes")

  GET_NOTE = StatelessMcp::ToolDeclaration.new(title: "Get a note", description: "Gets one note by its id.") do
    argument :note_id, :integer, "The note's id", required: true
  end

  use StatelessMcp::Middleware, server: SERVER

  # Runs only for requests the middleware has checked.
  post "/mcp" do
    content_type :json
    halt 202 unless rpc.key?("id") # Notifications have no response.

    case rpc["method"]
    when "server/discover" then success StatelessMcp::Result.discover(SERVER, capabilities: { tools: {} })
    when "tools/list" then success StatelessMcp::Result.complete({ tools: [GET_NOTE.to_h("get_note", SERVER)] }, cacheable: true)
    when "tools/call" then call_tool
    else error StatelessMcp::Rpc::ErrorCode::METHOD_NOT_FOUND, "Method not found"
    end
  end

  helpers do
    # The parsed JSON-RPC body, left in the env by the middleware.
    def rpc
      env[StatelessMcp::REQUEST_ENV_KEY]
    end

    def call_tool
      name, arguments = rpc["params"].values_at("name", "arguments")
      return error(StatelessMcp::Rpc::ErrorCode::INVALID_PARAMS, "Unknown tool: #{name}") unless name == "get_note"

      GET_NOTE.input_schema(SERVER).validate_arguments(arguments || {})
      note = NOTES[arguments["note_id"]]
      success note ? StatelessMcp::Result.tool(id: arguments["note_id"], text: note) : StatelessMcp::Result.refusal("No note #{arguments["note_id"]}")
    rescue MCP::Tool::InputSchema::ValidationError => invalid
      success StatelessMcp::Result.refusal(invalid.message)
    end

    def success(result)
      JSON.generate(StatelessMcp::Rpc.success(rpc["id"], result))
    end

    def error(code, message)
      status StatelessMcp::Rpc.status_for(code)
      JSON.generate(StatelessMcp::Rpc.error(rpc["id"], code, message))
    end
  end
end
```

```ruby
require_relative "app"

run NotesApp
```

Start it with `bundle exec rackup` in `examples/sinatra`. The [curl request in the Rack guide](rack.md#trying-it-with-curl) works against it too.

## Authentication

The gem has no authentication. Until the app adds a check, anyone who can reach the endpoint can call every tool.

A `before` filter is the simplest check:

```ruby
before "/mcp" do
  halt 401, { "www-authenticate" => "Bearer" }, "" unless Rack::Utils.secure_compare(request.env["HTTP_AUTHORIZATION"].to_s, "Bearer #{ENV.fetch("MCP_TOKEN")}")
end
```

Sinatra runs filters after the app's middleware, so `StatelessMcp::Middleware` has already parsed the body by then. To check the token first, use Rack middleware such as `RequireToken` from the [Rack guide](rack.md#authentication), on a `use` line above `use StatelessMcp::Middleware`.

## Everything else

Server settings, the middleware's checks, the building blocks and testing work the same as in plain Rack. See the [Rack guide](rack.md).
