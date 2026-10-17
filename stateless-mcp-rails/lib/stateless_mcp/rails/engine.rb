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
      # so the app's sign-in, rate limits and Origin check cover it too.
      config.stateless_mcp.parent_controller = "ActionController::API"

      initializer "stateless_mcp.routing" do
        ActionDispatch::Routing::Mapper.include(Routing)
      end

      # After the app's own initializers, which may set config.stateless_mcp.
      initializer "stateless_mcp.default_server", after: :load_config_initializers do |app|
        settings = app.config.stateless_mcp.to_h.except(:parent_controller)
        settings[:name] ||= app.class.module_parent_name.underscore
        StatelessMcp::Rails.default_server = Server.new(**settings)
        app.config.middleware.use Middleware, server: StatelessMcp::Rails.default_server
      end
    end
  end
end
