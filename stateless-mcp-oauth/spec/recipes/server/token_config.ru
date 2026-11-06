# config.ru
map(MCP_OAUTH_SERVER.token_path) { run MCP_OAUTH_SERVER.token_app }
