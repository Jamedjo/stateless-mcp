require "stateless_mcp"
require "rails"
require "action_controller"

module StatelessMcp
  # Rails support: a tool is a controller action, routed by the Mcp-Method and
  # Mcp-Name headers. Inside StatelessMcp, `Rails` names this module, so the
  # framework itself is always written `::Rails`.
  module Rails
    # Raised when a routed action has no tool declaration to list it by.
    UndeclaredTool = Class.new(StandardError)

    class << self
      # The server built from config.stateless_mcp at boot. Only the engine
      # sets it, and only `mcp_server` without a server argument reads it.
      attr_writer :default_server

      def default_server
        @default_server or raise "The default MCP server is built from config.stateless_mcp when the app boots, and it hasn't booted yet"
      end
    end
  end
end

require_relative "rails/routing"
require_relative "rails/controller"
require_relative "rails/server_actions"
require_relative "rails/engine"
