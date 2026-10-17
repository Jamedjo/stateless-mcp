# stateless-mcp

Serves the [Model Context Protocol](https://modelcontextprotocol.io/specification/2026-07-28) from Ruby, the stateless way: every request carries its own protocol version and is answered on its own, with a plain JSON body. Nothing holds a session or a stream open, so any process behind a load balancer can take any call.

Two gems live in this repository and are released together, always at the same version:

| Gem | For |
|---|---|
| [`stateless-mcp`](stateless-mcp) | Any Rack app. Depends only on the [`mcp`](https://github.com/modelcontextprotocol/ruby-sdk) gem and `rack` |
| [`stateless-mcp-rails`](stateless-mcp-rails) | Rails apps, where a tool is an ordinary controller action |

> **Status:** unreleased. Nothing is on RubyGems yet.

## A server in a Rails app

```ruby
# Gemfile
gem "stateless-mcp-rails"

# config/application.rb
config.stateless_mcp.name = "notes"
config.stateless_mcp.parent_controller = "Mcp::BaseController"

# config/routes.rb
mcp_server module: "mcp" do
  mcp_resource :notes, only: [:index, :show]
end

# app/controllers/mcp/base_controller.rb
class Mcp::BaseController < ActionController::API
  include StatelessMcp::Rails::Controller

  before_action :authenticate # the app's own sign-in
end

# app/controllers/mcp/notes_controller.rb
class Mcp::NotesController < Mcp::BaseController
  tool :show, "Gets one note.", title: "Get a note" do
    argument :note_id, :integer, "The note id from list_notes", required: true
  end
  def show
    note = Note.find_by(id: tool_params[:note_id]) or raise StatelessMcp::InvalidArgument, "No note #{tool_params[:note_id]}"
    render_tool id: note.id, title: note.title, body: note.body
  end

  # tool :index, ... and def index, likewise
end
```

That serves `list_notes` and `get_note` at `/mcp`, with `server/discover` and `tools/list` answered from the config and routes. The [Rails README](stateless-mcp-rails) has the rest.

## Several servers

Each server is a `StatelessMcp::Server` with its own path, name and limits. A second one gets its own middleware and its own routes, and lists only its own tools:

```ruby
# config/application.rb
ADMIN_MCP = StatelessMcp::Server.new(path: "/admin/mcp", name: "admin", max_body_bytes: 16_384)
config.middleware.use StatelessMcp::Middleware, server: ADMIN_MCP

# config/routes.rb
mcp_server ADMIN_MCP, module: "admin" do
  mcp_tool "count_notes", to: "notes#count"
end
```

## What the app keeps

Sign-in, rate limits and the `Origin` check are the app's: they go in the base controller its tools inherit from, or in middleware ahead of the server's. OAuth, for hosted clients such as claude.ai, will follow as an optional part of these gems, and clients on protocol revisions before 2026-07-28 may follow too.

## What comes from the `mcp` gem

Protocol constants, error codes and version lists, the `_meta` request envelope, argument validation through `MCP::Tool::InputSchema`, and the shape of each `tools/list` entry. Upgrading `mcp` brings new protocol versions. The header check and `server/discover` aren't public in `mcp`, so they're written here, and are kept in step with it.

## Development

```sh
bundle install
(cd stateless-mcp && bundle exec rspec)
(cd stateless-mcp-rails && bundle exec rspec)
bundle exec rubocop
```

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or https://www.apache.org/licenses/LICENSE-2.0)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or https://opensource.org/licenses/MIT)

at your option.

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.
