# Rails

This guide uses the `stateless-mcp-rails` gem. Each MCP tool is an ordinary route and controller action, and the gem builds `tools/list` from the routes.

- [Quick start](#quick-start)
- [Configuration](#configuration)
- [Routes](#routes)
- [Declaring tools](#declaring-tools)
- [Writing actions](#writing-actions)
- [Errors](#errors)
- [Paging ActiveRecord](#paging-activerecord)
- [Authentication](#authentication)
- [Several servers](#several-servers)
- [Testing](#testing)

## Quick start

This serves one tool, `get_note`, at `/mcp`. The app doesn't boot until it sets how MCP requests are authenticated. This example has no sign-in, so it sets `allow_unauthenticated`; [Authentication](#authentication) shows a base controller with sign-in instead:

```ruby
# config/application.rb
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

The gem handles `server/discover` and `tools/list` with the config and the routes. Rails routes each `tools/call` to the tool's action, using the `Mcp-Method` and `Mcp-Name` headers of the request.

## Configuration

The gem builds a default server from `config.stateless_mcp`, and adds its middleware to the app. Set these in `config/application.rb` or an initializer:

| Setting | Default | Meaning |
|---|---|---|
| `path` | `"/mcp"` | The endpoint's absolute path |
| `name` | The app's module name, underscored | The server name that clients show |
| `version`, `title`, `instructions` | `"1.0.0"`, none, none | The rest of the server's description |
| `max_body_bytes` | 1 MB | The largest request body accepted |
| `page_size`, `max_page_size` | 20, 100 | Default and largest page size for paginated tools |
| `check_origin`, `allowed_origins` | `true`, none | The [Origin check](../README.md#the-origin-check) |
| `tool_verbs` | `index: "list", show: "get", …` | How `mcp_resource` names a resource's tools |
| `parent_controller` | `"ActionController::API"` | The parent class of the gem's server controller. The app doesn't boot until this is set to the app's own base controller, or `allow_unauthenticated` is `true` |
| `allow_unauthenticated` | `false` | `true` boots the app with the default `parent_controller`, for a server that is open on purpose |

All but `parent_controller` and `allow_unauthenticated` are [server settings](rack.md#server-settings). An invalid setting stops the app from booting, with an error that names the setting.

## Routes

`mcp_server` draws a server's routes. Each macro inside it routes one or more tools:

```ruby
# config/routes.rb
mcp_server module: "mcp" do
  mcp_resource :notes, only: [:index, :show] do
    mcp_member :body
  end
  mcp_tool "search", to: "search#show"
end
```

Those routes give these tools:

| Macro | Tool | Action |
|---|---|---|
| `mcp_resource :notes, only: [:index]` | `list_notes` | `mcp/notes#index` |
| `mcp_resource :notes, only: [:show]` | `get_note` | `mcp/notes#show` |
| `mcp_member :body` | `get_note_body` | `mcp/notes#body` |
| `mcp_tool "search", to: "search#show"` | `search` | `mcp/search#show` |

`mcp_resource` names each action's tool with the server's `tool_verbs`.

`mcp_server` also routes `server/discover` and `tools/list`. For anything else, the response is:

- a 404 with `-32601` for an unknown method;
- `-32602` for a call to a tool with no route;
- an empty 202 for a notification.

`tools/list` lists exactly the routed tools, in route order. `bin/rails routes -g mcp` shows them all.

`mcp_server` uses its server's own path, so put it outside any `namespace` or path scope. `module:` and other scope options apply to the tools' controllers.

## Declaring tools

Include `StatelessMcp::Rails::Controller` in the tools' base controller, and declare each tool above its action:

```ruby
class Mcp::NotesController < Mcp::BaseController
  tool :index, "Lists notes, newest first.", title: "List notes" do
    argument :tag, :string, "Only notes with this tag"
    argument :created_after, :datetime, "ISO 8601 date or time"
    paginated "notes"
  end
  def index
    notes = Note.all
    notes = notes.select { |note| note.tags.include?(tool_params[:tag]) } if tool_params[:tag].present?
    page, next_cursor = paginate_list(notes)
    render_tool notes: page.map { |note| { id: note.id, title: note.title } }, next_cursor: next_cursor
  end
end
```

A controller declares its tools with these class methods:

| Declaration | Use |
|---|---|
| `tool action, description, title:, annotations:` | The tool for an action, as `tools/list` shows it. A tool is marked read-only unless `annotations:` is given |
| `argument name, type, description, required:, **keywords` | One argument. Types are JSON Schema types, plus `:datetime`, sent as a string. Keywords such as `enum:` are added to the schema unchanged |
| `paginated noun` | Adds `limit` and `cursor` arguments, described with the server's page sizes |

The gem checks a call's arguments against the schema before the action runs. For a missing or wrongly typed argument, the response is a tool error with a message for the model. If `arguments` isn't a JSON object, the response is a `-32602` error.

## Writing actions

Actions use these helpers:

| Helper | Use |
|---|---|
| `tool_params` | Strong parameters permitting exactly the declared arguments |
| `tool_time(name)` | A `:datetime` argument as a `Time`. Anything other than ISO 8601 is a tool error |
| `page_limit` | The page size the call asked for, within the server's limits |
| `paginate_list(items)` | One page of a list, and a `next_cursor` if more items remain |
| `paginate_text(part_size) { \|start, length\| … }` | One part of a long text, read a slice at a time, and a `next_cursor` if more text remains |
| `render_tool(hash)` | Renders the hash as JSON text, without nil values |
| `refuse(message)` | Renders a tool error with a message for the model |
| `raise StatelessMcp::InvalidArgument, message` | The same tool error, from anywhere in the action |
| `mcp_server`, `mcp_request` | The server for this request, and the parsed JSON-RPC body |

A tool result is JSON in one text block, with no `structuredContent`. The tools declare no `outputSchema`, and clients pass the text to the model either way.

## Errors

A cursor that this gem didn't create is a tool error.

The gem reports any other exception that the action doesn't rescue to `Rails.error`, and the client sees only `Internal error`. For an error with its own HTTP status in Rails, such as a rate limit's 429, the response has that status.

## Paging ActiveRecord

`paginate_list` pages by position. That suits data that doesn't change between calls. For records that do change, page by key with an optional module. Neither gem depends on ActiveRecord, so the app requires the module itself:

```ruby
require "stateless_mcp/rails/active_record"

class Mcp::BaseController < ActionController::API
  include StatelessMcp::Rails::Controller
  include StatelessMcp::Rails::RecordPagination
end

def index
  page, next_cursor = paginate(Note.where(user: current_user))
  render_tool notes: page.map { |note| { id: note.id, title: note.title } }, next_cursor: next_cursor
end
```

`paginate(records, limit: page_limit)` orders records newest first by `(created_at, id)`, and starts each page after the last record of the previous one. A deep page costs the same as the first, and new records don't shift later pages. Integer and string ids both work.

## Authentication

The gem has no authentication of its own. Without a check, anyone who can reach the endpoint can call every tool, so the app doesn't boot until it sets one of these:

- `parent_controller`, set to a base controller of the app's own that authenticates;
- `allow_unauthenticated = true`, for a server that is open on purpose.

Whether the base controller authenticates is up to the app. Any `parent_controller` other than `ActionController::API` boots the app, so make sure that controller signs in every request.

Put sign-in and rate limits in a base controller for the tools. Set it as `parent_controller` too, so the gem's server controller for `server/discover` and `tools/list` inherits the same checks:

```ruby
# config/application.rb
config.stateless_mcp.parent_controller = "Mcp::BaseController"

# app/controllers/mcp/base_controller.rb
class Mcp::BaseController < ActionController::API
  include StatelessMcp::Rails::Controller

  before_action :authenticate # the app's own sign-in
  rate_limit to: 20, within: 1.minute, by: -> { current_user.id }, scope: "mcp"
end
```

A tool controller that doesn't inherit from the base controller has no sign-in, even when `parent_controller` is set.

## Several servers

To add a server beside the default one, build it in code, add its middleware, and name it in the routes:

```ruby
# config/application.rb
ADMIN_MCP = StatelessMcp::Server.new(path: "/admin/mcp", name: "admin", max_body_bytes: 16_384)
config.middleware.use StatelessMcp::Middleware, server: ADMIN_MCP

# config/routes.rb
mcp_server ADMIN_MCP, module: "admin", controller: "admin/mcp_server" do
  mcp_tool "count_notes", to: "notes#count"
end
```

Each server's `tools/list` shows only the tools routed to its path, and each server has its own limits.

`controller:` is optional. It names a server controller of the app's own, for a server that needs a different base controller. That controller includes `StatelessMcp::Rails::ServerActions`.

## Testing

Request specs can post to the endpoint with `rack-test`, with the headers and `_meta` envelope from the [Rack guide's testing section](rack.md#testing). The gem's own specs do this against a small app in `stateless-mcp-rails/spec/dummy`.
