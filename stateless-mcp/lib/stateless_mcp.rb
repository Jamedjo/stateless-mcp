require "mcp"
require_relative "stateless_mcp/version"

# Serves the 2026-07-28 Model Context Protocol without sessions: every request
# carries its own protocol version and is answered on its own, so any process
# can take any call.
module StatelessMcp
end
