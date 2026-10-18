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

    # Raised at boot when the app has set neither parent_controller nor
    # allow_unauthenticated, as the tools would be open to anyone.
    AuthenticationNotConfigured = Class.new(Server::Invalid)

    DEFAULT_PARENT_CONTROLLER = "ActionController::API"

    class << self
      # The server built from config.stateless_mcp at boot. Only the engine
      # sets it, and only `mcp_server` without a server argument reads it.
      attr_writer :default_server

      def default_server
        @default_server or raise "The default MCP server is built from config.stateless_mcp when the app boots, and it hasn't booted yet"
      end

      # The default server, from the settings in config.stateless_mcp.
      def build_default_server(settings, default_name:)
        check_authentication(settings)
        server_settings = settings.except(:parent_controller, :allow_unauthenticated)
        server_settings[:name] ||= default_name
        Server.new(**server_settings)
      end

      private

      # A parent controller of the app's own is trusted to authenticate. The
      # gem can't tell whether it does, only that the app has chosen one.
      def check_authentication(settings)
        return if settings[:allow_unauthenticated] == true
        return if settings.fetch(:parent_controller, DEFAULT_PARENT_CONTROLLER).to_s != DEFAULT_PARENT_CONTROLLER
        raise AuthenticationNotConfigured, "config.stateless_mcp.parent_controller is #{DEFAULT_PARENT_CONTROLLER}, so anyone who can reach the MCP endpoint can call every tool. " \
          "Set config.stateless_mcp.parent_controller to a controller that authenticates, such as \"Mcp::BaseController\", " \
          "or set config.stateless_mcp.allow_unauthenticated = true for a server that is open on purpose."
      end
    end
  end
end

require_relative "rails/routing"
require_relative "rails/controller"
require_relative "rails/server_actions"
require_relative "rails/tools_report"
require_relative "rails/engine"
