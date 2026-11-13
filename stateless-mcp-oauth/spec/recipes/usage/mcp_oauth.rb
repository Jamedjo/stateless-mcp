# config/initializers/mcp_oauth.rb
Rails.application.config.stateless_mcp.protected_resource = StatelessMcp::OAuth::ProtectedResource.new(
  resource: "https://notes.example/mcp",
  authorization_server: "https://notes.example",
  storage: McpOAuthStorage.new
)
