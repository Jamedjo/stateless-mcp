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
