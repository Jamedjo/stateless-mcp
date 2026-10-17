module StatelessMcp
  module Rails
    # Turns a controller's actions into MCP tools. Include it in the base
    # controller the app's tools inherit from, and declare each tool beside its
    # action:
    #
    #   tool :index, "Lists notes, newest first.", title: "List notes" do
    #     argument :tag, :string, "Only notes with this tag"
    #     paginated "notes"
    #   end
    module Controller
      extend ActiveSupport::Concern

      included do
        class_attribute :mcp_tools, instance_writer: false, default: {}
        # MCP clients accept JSON or an event stream, and every answer goes back
        # as JSON whichever they listed first.
        prepend_before_action { request.format = :json }
      end

      class_methods do
        # Declares the tool an action serves, as tools/list shows it. The block
        # declares its arguments; see StatelessMcp::ToolDeclaration.
        def tool(action, description, title:, annotations: ToolDeclaration::READ_ONLY, &arguments)
          self.mcp_tools = mcp_tools.merge(action.to_s => ToolDeclaration.new(title: title, description: description, annotations: annotations, &arguments))
        end

        def mcp_tool_declaration(action)
          mcp_tools.fetch(action.to_s) { raise UndeclaredTool, "#{name}##{action} is routed as a tool but declares none; declare it with `tool :#{action}, ...`" }
        end
      end

      private

      # The server this request was routed to.
      def mcp_server
        request.get_header(Server::ENV_KEY) or raise "No StatelessMcp::Middleware serves #{request.path}; is the server's middleware in the app's stack?"
      end

      # The parsed JSON-RPC body.
      def mcp_request
        request.get_header(REQUEST_ENV_KEY) || {}
      end

      def render_result(result)
        render json: Rpc.success(mcp_request["id"], result)
      end

      def render_rpc_error(code, message, data: nil)
        render json: Rpc.error(mcp_request["id"], code, message, data: data), status: Rpc.status_for(code)
      end
    end
  end
end
