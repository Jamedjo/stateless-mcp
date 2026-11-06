require "stateless-mcp"
require_relative "oauth/claims"
require_relative "oauth/error"
require_relative "oauth/storage"
require_relative "oauth/metadata_app"
require_relative "oauth/invalid_token"
require_relative "oauth/pkce"
require_relative "oauth/client_id"
require_relative "oauth/client_metadata"
require_relative "oauth/document_fetcher"
require_relative "oauth/document_transport"
require_relative "oauth/memory_cache"
require_relative "oauth/protected_resource"
require_relative "oauth/authorization_server"
require_relative "oauth/authorization_request"

module StatelessMcp
  # OAuth for MCP clients. It has an authorization server, which signs people
  # in, and access token checks for each MCP request. Grants and tokens are
  # stored through a subclass of StatelessMcp::OAuth::Storage.
  module OAuth
  end
end
