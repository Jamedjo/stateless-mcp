module StatelessMcp
  module Rails
    # The protocol's own methods, which mcp_server routes to the server
    # controller. The gem's StatelessMcp::Rails::ServerController includes
    # this; an app that writes its own server controller includes it there.
    module ServerActions
      extend ActiveSupport::Concern

      include Controller

      def discover
        render_result Result.discover(mcp_server, capabilities: capabilities)
      end

      def tools
        tools = Routing.listed_tools(mcp_server, _routes).map(&:first)
        render_result Result.complete({ tools: tools }, cacheable: true)
      end

      # Any request no route claimed. A notification needs no answer, and a
      # tool that isn't routed is a bad argument to tools/call rather than an
      # unknown method.
      def unknown_method
        method = mcp_request["method"]
        return head(:accepted) if MCP::Methods.notification?(method)
        return render_rpc_error(Rpc::ErrorCode::INVALID_PARAMS, "Unknown tool: #{mcp_request.dig("params", "name")}") if method == MCP::Methods::TOOLS_CALL
        render_rpc_error(Rpc::ErrorCode::METHOD_NOT_FOUND, "Method not found", data: method)
      end

      private

      def capabilities
        { tools: {} }
      end
    end
  end
end
