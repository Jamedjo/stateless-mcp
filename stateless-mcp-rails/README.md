# stateless-mcp-rails

Rails support for [stateless-mcp](https://github.com/Jamedjo/stateless-mcp): Model Context Protocol tools as ordinary routes and controller actions. Rails routes pick a tool from the `Mcp-Method` and `Mcp-Name` headers that every 2026-07-28 request carries, and `tools/list` is drawn from those routes.

> **Status:** unreleased.

## Setup

```ruby
# Gemfile
gem "stateless-mcp-rails"
```

The engine builds a default server from `config.stateless_mcp` and puts its middleware on the app's stack. Every setting has a default, so none is required:

```ruby
# config/application.rb, or an initializer
config.stateless_mcp.path = "/mcp"
config.stateless_mcp.name = "notes"
config.stateless_mcp.version = "1.2.0"
config.stateless_mcp.instructions = "Notes are private to whoever wrote them."
config.stateless_mcp.max_body_bytes = 64.kilobytes
config.stateless_mcp.page_size = 20
config.stateless_mcp.max_page_size = 100
config.stateless_mcp.parent_controller = "Mcp::BaseController"
```

`name` defaults to the app's module name, underscored. The rest are [`StatelessMcp::Server`'s settings](../stateless-mcp#a-server); a setting the server can't serve stops the app booting with an error naming it.

## Routes

```ruby
# config/routes.rb
mcp_server module: "mcp" do
  mcp_resource :notes, only: [:index, :show] do
    mcp_member :body
  end
  mcp_tool "search", to: "search#show"
end
```

| Macro | Tool | Action |
|---|---|---|
| `mcp_resource :notes, only: [:index]` | `list_notes` | `mcp/notes#index` |
| `mcp_resource :notes, only: [:show]` | `get_note` | `mcp/notes#show` |
| `mcp_member :body` | `get_note_body` | `mcp/notes#body` |
| `mcp_tool "search", to: "search#show"` | `search` | `mcp/search#show` |

`mcp_resource` names each action's tool by the server's `tool_verbs`. `mcp_server` also routes the protocol's own methods, `server/discover` and `tools/list`, and answers anything else: an unknown method gets a 404 with `-32601`, a call to a tool that isn't routed gets `-32602`, and a notification gets a 202. `tools/list` is built from the routes, so a tool is listed exactly when it is routed, in the order it's drawn. `bin/rails routes -g mcp` shows them all.

`mcp_server` draws at its server's own path, so it goes outside any `namespace` or path scope; `module:` and other scope options apply to the tools' controllers.

## Controllers

Include `StatelessMcp::Rails::Controller` in the base controller the tools inherit from, and declare each tool beside its action:

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

  tool :show, "Gets one note.", title: "Get a note" do
    argument :note_id, :integer, "The note id from list_notes", required: true
  end
  def show
    note = Note.find_by(id: tool_params[:note_id]) or raise StatelessMcp::InvalidArgument, "No note #{tool_params[:note_id]}"
    render_tool id: note.id, title: note.title, body: note.body
  end
end
```

| Declaration | What it does |
|---|---|
| `tool action, description, title:, annotations:` | Declares the tool `tools/list` shows for an action. Tools are read-only unless `annotations:` says otherwise |
| `argument name, type, description, required:, **keywords` | One argument. Types are JSON Schema types, plus `:datetime`, which travels as a string. Keywords such as `enum:` go into the schema as given |
| `paginated noun` | Adds `limit` and `cursor` arguments, described with the server's page sizes |

A call's arguments are checked against the declared schema before the action runs. A missing or mistyped argument is refused with a message the model can act on, and arguments that aren't an object are a malformed call, answered with `-32602`.

| Helper | What it does |
|---|---|
| `tool_params` | Strong parameters permitting exactly the declared arguments |
| `tool_time(name)` | Reads a `:datetime` argument as a `Time`, refusing anything that isn't ISO 8601 |
| `page_limit` | The page size the call asked for, held to the server's limits |
| `paginate_list(items)` | One page of a list, and the `next_cursor` for the next while more remain |
| `paginate_text(part_size) { \|start, length\| … }` | Long text in parts, read a slice at a time, with a `next_cursor` while more remains |
| `render_tool(hash)` | Answers with the hash as JSON text, leaving out nil values |
| `refuse(message)` | Answers with an error the model can read and act on |
| `raise StatelessMcp::InvalidArgument, message` | The same refusal, from anywhere in the action |
| `mcp_server`, `mcp_request` | The server this request was routed to, and its parsed JSON-RPC body |

Results are text only: the JSON goes in one text block, with no `structuredContent`, since the tools declare no `outputSchema` and clients hand the text to the model either way.

A cursor this library didn't issue is refused. Any other exception the action doesn't rescue is reported to `Rails.error` and reaches the client only as `Internal error`, except the errors Rails answers with a status of its own, such as a rate limit's 429.

## Auth, rate limits and Origin

These are the app's, and the gem doesn't decide them. They belong in the base controller, which the gem's server controller inherits from too, through `config.stateless_mcp.parent_controller`:

```ruby
class Mcp::BaseController < ActionController::API
  include StatelessMcp::Rails::Controller

  before_action :authenticate
  before_action :refuse_cross_origin
  rate_limit to: 20, within: 1.minute, by: -> { current_user.id }, scope: "mcp"

  private

  # A page in a browser must not drive the tools with someone's credentials.
  def refuse_cross_origin
    head :forbidden if request.origin.present? && request.origin != request.base_url
  end
end
```

Without `parent_controller`, the server controller inherits from `ActionController::API`, and `server/discover` and `tools/list` are open to anyone who can reach the endpoint.

OAuth will slot in as middleware ahead of the server's: it checks the bearer token before the body is read, answers a request without one with a `401` and a `WWW-Authenticate` challenge, and leaves the verified token in the Rack env for the base controller to sign the caller in from.

## Several servers

A server other than the default is built in code, given its own middleware, and named in the routes:

```ruby
# config/application.rb
ADMIN_MCP = StatelessMcp::Server.new(path: "/admin/mcp", name: "admin", max_body_bytes: 16_384)
config.middleware.use StatelessMcp::Middleware, server: ADMIN_MCP

# config/routes.rb
mcp_server ADMIN_MCP, module: "admin", controller: "admin/mcp_server" do
  mcp_tool "count_notes", to: "notes#count"
end
```

Each server lists only the tools routed to its path and keeps its own limits. `controller:` names a server controller of the app's own, for a server that needs a different base controller; it includes `StatelessMcp::Rails::ServerActions`.

## License

Licensed under either of Apache-2.0 or MIT, at your option.
