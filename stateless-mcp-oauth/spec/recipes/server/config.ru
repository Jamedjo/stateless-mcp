# config.ru
map(MCP_OAUTH_SERVER.metadata_path) { run MCP_OAUTH_SERVER.metadata_app }
