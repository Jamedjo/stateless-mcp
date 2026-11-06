require "stateless-mcp"
require_relative "oauth/claims"
require_relative "oauth/error"
require_relative "oauth/storage"
require_relative "oauth/metadata_app"
require_relative "oauth/pkce"
require_relative "oauth/client_id"
require_relative "oauth/client_metadata"
require_relative "oauth/document_fetcher"
require_relative "oauth/document_transport"
require_relative "oauth/memory_cache"

module StatelessMcp
  # An OAuth authorization server for MCP clients. Its state is stored in the
  # app's tables, through a StatelessMcp::OAuth::Storage subclass the app
  # writes.
  module OAuth
  end
end
