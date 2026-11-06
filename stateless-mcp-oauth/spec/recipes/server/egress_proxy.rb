# config/initializers/mcp_oauth.rb, in place of the MCP_OAUTH_SERVER above
MCP_OAUTH_SERVER = StatelessMcp::OAuth::AuthorizationServer.new(
  issuer: "https://notes.example",
  protected_resources: [MCP_OAUTH],
  client_metadata_transport: StatelessMcp::OAuth::DocumentTransport.new(proxy: ENV.fetch("EGRESS_PROXY_URL"))
)
