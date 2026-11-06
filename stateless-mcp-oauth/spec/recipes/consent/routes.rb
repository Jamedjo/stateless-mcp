# config/routes.rb, inside Rails.application.routes.draw
get MCP_OAUTH_SERVER.authorization_path, to: "mcp_authorizations#new"
post MCP_OAUTH_SERVER.authorization_path, to: "mcp_authorizations#create"
