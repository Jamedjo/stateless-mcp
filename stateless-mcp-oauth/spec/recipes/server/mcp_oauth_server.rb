# config/initializers/mcp_oauth.rb, after MCP_OAUTH
MCP_OAUTH_SERVER = StatelessMcp::OAuth::AuthorizationServer.new(
  issuer: "https://notes.example",
  protected_resources: [MCP_OAUTH]
)
