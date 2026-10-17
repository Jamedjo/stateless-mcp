module StatelessMcp
  module Rails
    # Answers the protocol's own methods, such as server/discover and
    # tools/list, for every server drawn with mcp_server. It inherits from
    # config.stateless_mcp.parent_controller, so whatever guards the app's
    # tools guards these too.
    class ServerController < ::Rails.application.config.stateless_mcp.parent_controller.constantize
      include ServerActions
    end
  end
end
