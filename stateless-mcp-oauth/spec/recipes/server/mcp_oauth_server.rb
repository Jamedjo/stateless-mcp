# config/initializers/mcp_oauth.rb, after the protected resource
MCP_OAUTH_SERVER = StatelessMcp::OAuth::AuthorizationServer.new(issuer: "https://notes.example")
