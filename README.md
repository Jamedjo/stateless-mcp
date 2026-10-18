# stateless-mcp

Ruby gems for serving [Model Context Protocol](https://modelcontextprotocol.io/specification/2026-07-28) tools over plain HTTP, without sessions, from Rack, Sinatra or Rails.

> **Status:** unreleased. Nothing is on RubyGems yet.

In the 2026-07-28 revision of MCP, each request includes its protocol version, and the response is a plain JSON body. There is no session or open stream between requests, so any process behind a load balancer can handle any request.

## Installation

Add the gem for your framework to the app's Gemfile:

```ruby
gem "stateless-mcp"        # Rack or Sinatra
gem "stateless-mcp-rails"  # Rails, which includes stateless-mcp
```

Then run `bundle install`.

Until the first release, use a checkout of this repository instead, as the examples do:

```ruby
gem "stateless-mcp", path: "../stateless-mcp/stateless-mcp"
```

## A first look

Each of these serves a tool called `get_note` at `/mcp`.

### Rails

A tool is a route and a controller action. The gem builds `tools/list` from the routes:

```ruby
# config/application.rb, until the app adds sign-in: see Authentication
config.stateless_mcp.allow_unauthenticated = true

# config/routes.rb
mcp_server module: "mcp" do
  mcp_resource :notes, only: [:show]
end

# app/controllers/mcp/notes_controller.rb
class Mcp::NotesController < ActionController::API
  include StatelessMcp::Rails::Controller

  tool :show, "Gets one note.", title: "Get a note" do
    argument :note_id, :integer, "The note's id", required: true
  end
  def show
    note = Note.find_by(id: tool_params[:note_id]) or return refuse("No note #{tool_params[:note_id]}")
    render_tool id: note.id, title: note.title, body: note.body
  end
end
```

The [Rails guide](docs/rails.md) has the rest.

### Rack

`StatelessMcp::Middleware` checks each request and puts the parsed JSON-RPC body in the Rack env. The app then handles each MCP method:

```ruby
SERVER = StatelessMcp::Server.new(name: "notes")
use StatelessMcp::Middleware, server: SERVER

# In the app's call(env):
rpc = env[StatelessMcp::REQUEST_ENV_KEY]
if rpc["method"] == "tools/call"
  note = NOTES[rpc.dig("params", "arguments", "note_id")]
  StatelessMcp::Rpc.success(rpc["id"], StatelessMcp::Result.tool(text: note))
end
```

The [Rack guide](docs/rack.md) has a full, tested example.

### Sinatra

There is no Sinatra-specific gem. A Sinatra app uses the same middleware, and handles the MCP methods in one route:

```ruby
class NotesApp < Sinatra::Base
  use StatelessMcp::Middleware, server: SERVER

  post "/mcp" do
    rpc = env[StatelessMcp::REQUEST_ENV_KEY]
    case rpc["method"]
    when "tools/list" then success StatelessMcp::Result.complete({ tools: [GET_NOTE.to_h("get_note", SERVER)] }, cacheable: true)
    when "tools/call" then success StatelessMcp::Result.tool(text: NOTES[rpc.dig("params", "arguments", "note_id")])
    end
  end
end
```

The [Sinatra guide](docs/sinatra.md) has a full, tested example.

## Declaring a tool and its arguments

A tool declaration gives the tool's title, description and arguments, as `tools/list` shows them to clients. In Rails, declare it above the action:

```ruby
tool :index, "Lists notes, newest first.", title: "List notes" do
  argument :tag, :string, "Only notes with this tag"
  argument :created_after, :datetime, "ISO 8601 date or time"
  paginated "notes"
end
```

In Rack or Sinatra, the same block goes in `StatelessMcp::ToolDeclaration.new(title:, description:)`.

Argument types are JSON Schema types, plus `:datetime`. In Rails, the gem checks each call's arguments against the declaration before the action runs. See [declaring tools in Rails](docs/rails.md#declaring-tools) or [in Rack](docs/rack.md#declaring-arguments).

## Returning results and tool errors

A tool result is JSON in one text block. A tool error is a result with a message for the model, such as "No note 9", so the model can try again with different arguments:

```ruby
# Rails
render_tool id: note.id, title: note.title
refuse "No note #{tool_params[:note_id]}"

# Rack or Sinatra
StatelessMcp::Result.tool(id: note.id, title: note.title)
StatelessMcp::Result.refusal("No note 9")
```

In Rails, `raise StatelessMcp::InvalidArgument, message` gives the same tool error from anywhere in the action. See [writing actions](docs/rails.md#writing-actions) and [the building blocks](docs/rack.md#building-blocks).

## Paging lists and long text

`paginated` in a declaration adds `limit` and `cursor` arguments. The action then returns one page and a `next_cursor`:

```ruby
page, next_cursor = paginate_list(notes)
render_tool notes: page.map { |note| { id: note.id, title: note.title } }, next_cursor: next_cursor
```

`paginate_text` splits a long text into parts in the same way. For ActiveRecord, an optional module pages by key, so new records don't shift later pages: see [paging in Rails](docs/rails.md#paging-activerecord). In Rack or Sinatra, `StatelessMcp::Pagination` has the same functions.

## Authentication

The gems have no authentication. Until the app adds a check, anyone who can reach the endpoint can call every tool. In Rails, the app doesn't boot until it sets `parent_controller` to a base controller that authenticates, or sets `allow_unauthenticated = true`.

This table gives the usual place for the check in each framework:

| Framework | Check | Example |
|---|---|---|
| Rails | `before_action` in the tools' base controller, set as `parent_controller` | [Rails guide](docs/rails.md#authentication) |
| Rack | Middleware listed before `StatelessMcp::Middleware` | [Rack guide](docs/rack.md#authentication) |
| Sinatra | A `before "/mcp"` filter, or Rack middleware | [Sinatra guide](docs/sinatra.md#authentication) |

OAuth support is planned.

## The Origin check

The MCP spec requires servers to check the `Origin` header. Without that check, a page on another site could call the tools from a visitor's browser, with the visitor's cookies.

`StatelessMcp::Middleware` returns a 403 for a request whose `Origin` is a different site from the server. Requests without an `Origin` header, such as those from desktop clients, are not affected.

To allow another origin, or turn the check off:

```ruby
StatelessMcp::Server.new(allowed_origins: ["https://app.example"])
StatelessMcp::Server.new(check_origin: false)

# Rails
config.stateless_mcp.allowed_origins = ["https://app.example"]
```

## Settings

A server has a path, a name and limits, each with a default:

```ruby
# Rack or Sinatra
SERVER = StatelessMcp::Server.new(path: "/mcp", name: "notes", max_body_bytes: 64 * 1024)

# Rails, in config/application.rb or an initializer
config.stateless_mcp.name = "notes"
config.stateless_mcp.max_body_bytes = 64.kilobytes
```

The [Rack guide](docs/rack.md#server-settings) and the [Rails guide](docs/rails.md#configuration) list every setting.

## Several servers in one app

An app can serve several MCP endpoints, each with its own path, tools and limits. Each server has its own middleware:

```ruby
admin = StatelessMcp::Server.new(path: "/admin/mcp", name: "admin", max_body_bytes: 16_384)
use StatelessMcp::Middleware, server: admin
```

In Rails, pass the server to `mcp_server` in the routes too. See [several servers in Rails](docs/rails.md#several-servers) or [in Rack](docs/rack.md#several-servers).

## Testing

A test sends a POST with the MCP headers and a `_meta` envelope in the body. [`examples/smoke_check.rb`](examples/smoke_check.rb) shows the format with `Rack::MockRequest`, and [testing in the Rack guide](docs/rack.md#testing) lists what each request needs.

## Limits

The gems have these limits:

- Only the 2026-07-28 protocol revision. Requests from clients on earlier revisions get an error.
- Tools only: no resources or prompts.
- One JSON-RPC request per HTTP request, with no batches.
- A tool result is JSON in one text block, with no `structuredContent`.

## Development

These commands run both gems' specs and rubocop:

```sh
bundle install
(cd stateless-mcp && bundle exec rspec)
(cd stateless-mcp-rails && bundle exec rspec)
bundle exec rubocop
```

Each example has its own Gemfile, so the gems' specs never load Sinatra. Each smoke check sends requests to its example, and compares the example's code with the copy in its guide:

```sh
(cd examples/rack && bundle install && bundle exec ruby smoke.rb)
(cd examples/sinatra && bundle install && bundle exec ruby smoke.rb)
```

The protocol constants, error codes, `_meta` envelope, argument validation and `tools/list` entry format come from the [`mcp`](https://github.com/modelcontextprotocol/ruby-sdk) gem. These gems add the header check and `server/discover`, which `mcp` doesn't make public.

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or https://www.apache.org/licenses/LICENSE-2.0)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or https://opensource.org/licenses/MIT)

at your option.

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.
