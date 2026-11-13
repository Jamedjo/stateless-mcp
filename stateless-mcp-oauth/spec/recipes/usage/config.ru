# config.ru
use StatelessMcp::OAuth::RequireToken, protected_resource: MCP_OAUTH, server: SERVER
use StatelessMcp::Middleware, server: SERVER
run NotesMcp.new
