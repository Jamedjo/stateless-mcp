module StatelessMcp
  module Rails
    # Builds the default server from config.stateless_mcp and puts its
    # middleware on the app's stack. An engine rather than a plain railtie, so
    # the server controller under app/controllers is autoloaded and can
    # inherit from a controller of the app's.
    class Engine < ::Rails::Engine
      config.stateless_mcp = ActiveSupport::OrderedOptions.new
      # Every StatelessMcp::Server setting can be set here too, such as path,
      # name and max_body_bytes. The server controller inherits from this one,
      # so the app's sign-in and rate limits cover it too. Left as the default,
      # the app doesn't boot unless allow_unauthenticated is true.
      config.stateless_mcp.parent_controller = DEFAULT_PARENT_CONTROLLER
      config.stateless_mcp.allow_unauthenticated = false

      rake_tasks do
        namespace :mcp do
          desc "Lists each MCP server's tools. VERBOSE=1 adds each tool's argument schema"
          task tools: :environment do
            puts ToolsReport.new(::Rails.application.routes, verbose: ENV["VERBOSE"].present?)
          end
        end
      end

      initializer "stateless_mcp.routing" do
        ActionDispatch::Routing::Mapper.include(Routing)
      end

      # After the app's own initializers, which may set config.stateless_mcp.
      initializer "stateless_mcp.default_server", after: :load_config_initializers do |app|
        StatelessMcp::Rails.default_server = StatelessMcp::Rails.build_default_server(app.config.stateless_mcp.to_h, default_name: app.class.module_parent_name.underscore)
        app.config.middleware.use Middleware, server: StatelessMcp::Rails.default_server
      end
    end
  end
end
