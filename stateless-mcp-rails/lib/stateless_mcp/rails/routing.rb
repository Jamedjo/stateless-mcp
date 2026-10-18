module StatelessMcp
  module Rails
    # Route macros for config/routes.rb. Every MCP request is a POST to the
    # server's path, told apart by its Mcp-Method and Mcp-Name headers:
    #
    #   mcp_server module: "mcp" do
    #     mcp_resource :notes, only: [:index, :show] do
    #       mcp_member :body
    #     end
    #     mcp_tool "search", to: "search#show"
    #   end
    #
    # draws list_notes, get_note, get_note_body and search as tools, routed to
    # mcp/notes#index, #show, #body and mcp/search#show. tools/list is built
    # from these routes, so a tool is listed exactly when it is routed.
    module Routing
      SERVER_CONTROLLER = "stateless_mcp/rails/server"

      # The servers each route set draws, by path. An app has one route set, so
      # holding on to them costs nothing.
      DRAWN_SERVERS = Hash.new { |sets, route_set| sets[route_set] = {} }.compare_by_identity

      # Matches a request by the headers the middleware has already checked
      # against its body.
      class Constraint
        def initialize(method, name: nil)
          @method = method
          @name = name
        end

        def matches?(request)
          request.headers["Mcp-Method"] == @method && (@name.nil? || request.headers["Mcp-Name"] == @name)
        end
      end

      # Each tool routed to a server's path, as [name, controller class, action],
      # in the order the routes are drawn.
      def self.tools(server, route_set)
        route_set.routes.filter_map do |route|
          name = route.defaults[:mcp_tool]
          next unless name && route.path.spec.to_s == server.path
          [name, "#{route.defaults[:controller]}_controller".camelize.constantize, route.defaults[:action]]
        end
      end

      # Each tool's tools/list entry, with the controller and action it's
      # routed to. tools/list and `rake mcp:tools` both read this, so the two
      # always agree.
      def self.listed_tools(server, route_set)
        tools(server, route_set).map do |name, controller, action|
          [controller.mcp_tool_declaration(action).to_h(name, server), controller, action]
        end
      end

      # Each server drawn with mcp_server and still routed, in the order the
      # routes are drawn. Reading the routes first loads them if Rails has
      # deferred that.
      def self.servers(route_set)
        routed_paths = route_set.routes.map { |route| route.path.spec.to_s }
        DRAWN_SERVERS[route_set].values.select { |server| routed_paths.include?(server.path) }
      end

      # Draws a server's routes: its tools, from the block, and the protocol's
      # own methods, answered by the controller given. Options such as module:
      # scope the tools' controllers but not the server controller. The server
      # is the default one built from config.stateless_mcp unless another is
      # given.
      def mcp_server(server = nil, controller: SERVER_CONTROLLER, **options)
        server ||= StatelessMcp::Rails.default_server
        raise ArgumentError, "mcp_server draws at its server's own path, #{server.path}, so it can't be inside a path scope" if @scope[:path]
        @mcp_server = server
        DRAWN_SERVERS[@set][server.path] = server
        scope(as: nil, format: false) do
          mcp_method MCP::Methods::SERVER_DISCOVER, to: "#{controller}#discover"
          mcp_method MCP::Methods::TOOLS_LIST, to: "#{controller}#tools"
          scope(**options) { yield } if block_given?
          post server.path, to: "#{controller}#unknown_method", as: nil
        end
      ensure
        @mcp_server = nil
      end

      # A tool for each action, named by the server's tool_verbs: index on
      # notes is list_notes, show is get_note.
      def mcp_resource(resources, only:)
        @mcp_resource = resources.to_s
        Array(only).each do |action|
          verb = current_mcp_server.tool_verbs[action.to_sym] or raise ArgumentError, "No tool verb for :#{action}; add one to tool_verbs, or route it with mcp_member or mcp_tool"
          noun = action.to_sym == :index ? @mcp_resource : @mcp_resource.singularize
          mcp_tool "#{verb}_#{noun}", to: "#{@mcp_resource}##{action}"
        end
        yield if block_given?
      ensure
        @mcp_resource = nil
      end

      # A tool reading one more thing about a member of the resource it's
      # drawn in, named get_<singular>_<action>.
      def mcp_member(action, verb: "get")
        raise ArgumentError, "mcp_member belongs inside an mcp_resource block" unless @mcp_resource
        mcp_tool "#{verb}_#{@mcp_resource.singularize}_#{action}", to: "#{@mcp_resource}##{action}"
      end

      # The tool name is kept as a route default, which is where tools/list
      # reads it back from.
      def mcp_tool(name, to:)
        post current_mcp_server.path, to: to, constraints: Constraint.new(MCP::Methods::TOOLS_CALL, name: name.to_s), defaults: { mcp_tool: name.to_s }, as: nil
      end

      def mcp_method(method, to:)
        post current_mcp_server.path, to: to, constraints: Constraint.new(method), as: nil
      end

      private

      def current_mcp_server
        @mcp_server or raise ArgumentError, "MCP tools and methods are drawn inside an mcp_server block"
      end
    end
  end
end
