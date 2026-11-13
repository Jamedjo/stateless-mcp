# config.ru
MCP_OAUTH = StatelessMcp::OAuth::ProtectedResource.new(
  resource: "https://notes.example/mcp",
  authorization_server: "https://notes.example",
  storage: McpOAuthStorage.new
)
use StatelessMcp::OAuth::RequireToken, protected_resource: MCP_OAUTH, server: SERVER
use StatelessMcp::Middleware, server: SERVER
run NotesMcp.new
