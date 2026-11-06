require "stateless-mcp"
require_relative "oauth/claims"
require_relative "oauth/storage"
require_relative "oauth/metadata_app"

module StatelessMcp
  # An OAuth authorization server for MCP clients. Its state is stored in the
  # app's tables, through a StatelessMcp::OAuth::Storage subclass the app
  # writes.
  module OAuth
  end
end
