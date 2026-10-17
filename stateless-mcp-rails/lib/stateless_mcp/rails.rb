require "stateless_mcp"
require "rails"
require "action_controller"

module StatelessMcp
  # Rails support. Inside StatelessMcp, `Rails` names this module, so the
  # framework itself is always written `::Rails`.
  module Rails
  end
end
