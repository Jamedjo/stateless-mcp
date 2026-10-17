require "rails"
require "action_controller/railtie"
require "stateless-mcp-rails"

module Dummy
  # A second server, beside the default one built from config.stateless_mcp.
  ADMIN_MCP = StatelessMcp::Server.new(path: "/admin/mcp", name: "admin", max_body_bytes: 2048, page_size: 1, max_page_size: 3)

  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.logger = Logger.new(nil)
    config.secret_key_base = "dummy"
    config.active_support.deprecation = :raise

    config.stateless_mcp.name = "notes"
    config.stateless_mcp.version = "2.0.0"
    config.stateless_mcp.instructions = "Notes kept in memory, newest first."
    config.stateless_mcp.max_body_bytes = 4096
    config.stateless_mcp.page_size = 2
    config.stateless_mcp.parent_controller = "Mcp::BaseController"

    config.middleware.use StatelessMcp::Middleware, server: ADMIN_MCP
  end
end
