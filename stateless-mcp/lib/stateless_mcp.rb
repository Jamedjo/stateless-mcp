require "base64"
require "json"
require "rack"
require "stringio"
require "uri"
require "mcp"
require "mcp/server/transports/streamable_http_transport"
require_relative "stateless_mcp/version"

# Serves the 2026-07-28 Model Context Protocol without sessions: every request
# carries its own protocol version and is answered on its own, so any process
# can take any call.
module StatelessMcp
  # Raised with a message the model can act on, such as a date it couldn't
  # read. It is answered as a refused tool call, which the model sees, rather
  # than a protocol error, which it may not.
  InvalidArgument = Class.new(StandardError)

  # The parsed JSON-RPC body, which the middleware leaves in the Rack env.
  REQUEST_ENV_KEY = "stateless_mcp.request"

  # The grant behind a request's access token, which stateless-mcp-oauth's
  # RequireToken leaves in the Rack env. A client can't set it: Rack names every
  # request header's key with an HTTP_ prefix.
  GRANT_ENV_KEY = "stateless_mcp.oauth.grant"

  # Methods whose target is mirrored into the Mcp-Name header.
  NAME_BEARING_METHODS = MCP::Server::Transports::StreamableHTTPTransport::NAME_BEARING_METHODS

  # The tool name, or resource URI, that a request's Mcp-Name header must repeat.
  def self.target_name(body)
    params = body["params"]
    params["name"] || params["uri"] if NAME_BEARING_METHODS.include?(body["method"]) && params.is_a?(Hash)
  end
end

require_relative "stateless_mcp/rpc"
require_relative "stateless_mcp/refusal"
require_relative "stateless_mcp/server"
require_relative "stateless_mcp/cursor"
require_relative "stateless_mcp/pagination"
require_relative "stateless_mcp/request_body"
require_relative "stateless_mcp/header_check"
require_relative "stateless_mcp/middleware"
require_relative "stateless_mcp/result"
require_relative "stateless_mcp/tool_declaration"
