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
