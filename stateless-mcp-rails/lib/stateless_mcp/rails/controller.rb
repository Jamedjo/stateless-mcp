module StatelessMcp
  module Rails
    # Turns a controller's actions into MCP tools. Include it in the base
    # controller the app's tools inherit from, declare each tool beside its
    # action, read its arguments from tool_params, and answer with render_tool
    # or refuse:
    #
    #   tool :show, "Gets one note.", title: "Get a note" do
    #     argument :note_id, :integer, "The note id from list_notes", required: true
    #   end
    #   def show
    #     note = Note.find_by(id: tool_params[:note_id]) or return refuse("No note #{tool_params[:note_id]}")
    #     render_tool id: note.id, title: note.title
    #   end
    module Controller
      extend ActiveSupport::Concern

      included do
        class_attribute :mcp_tools, instance_writer: false, default: {}
        # MCP clients accept JSON or an event stream, and every answer goes back
        # as JSON whichever they listed first.
        prepend_before_action { request.format = :json }
        before_action :check_tool_arguments, if: :tool_call?
        rescue_from StandardError, with: :internal_error
        rescue_from InvalidArgument, with: ->(error) { refuse(error.message) }
        rescue_from Cursor::Invalid, with: -> { refuse("cursor must be a next_cursor from an earlier result") }
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

      def tool_call?
        params[:mcp_tool].present?
      end

      def tool_declaration
        self.class.mcp_tool_declaration(action_name)
      end

      # Strong parameters permitting exactly the declared arguments.
      def tool_params
        @tool_params ||= params.fetch(:params, {}).fetch(:arguments, {}).permit(*permitted_arguments)
      end

      # Reads a :datetime argument, refusing anything that isn't ISO 8601.
      def tool_time(name)
        value = tool_params[name]
        value.blank? ? nil : Time.zone.iso8601(value)
      rescue ArgumentError
        raise InvalidArgument, "#{name} must be an ISO 8601 date or time, like 2026-10-01 or 2026-10-01T09:00:00Z"
      end

      # The page size the call asked for, held to the server's limits.
      def page_limit
        Pagination.limit(tool_params[:limit], mcp_server)
      end

      # One page of a list, and the next_cursor for the page after.
      def paginate_list(items)
        Pagination.list(items, cursor: tool_params[:cursor], limit: page_limit)
      end

      # A long text in parts of part_size characters, and the next_cursor for
      # the part after. The block reads a slice of the text from a start
      # position and length.
      def paginate_text(part_size, &read)
        Pagination.text(tool_params[:cursor], part_size, &read)
      end

      def render_tool(payload)
        render_result Result.tool(payload)
      end

      # A refusal the model can read and act on, rather than a protocol error.
      def refuse(message)
        render_result Result.refusal(message)
      end

      def render_result(result)
        render json: Rpc.success(mcp_request["id"], result)
      end

      def render_rpc_error(code, message, data: nil)
        render json: Rpc.error(mcp_request["id"], code, message, data: data), status: Rpc.status_for(code)
      end

      # The arguments are checked against the raw JSON, before strong
      # parameters coerce anything. Arguments that aren't an object make the
      # call itself malformed, which is a protocol error.
      def check_tool_arguments
        arguments = mcp_request.dig("params", "arguments") || {}
        return render_rpc_error(Rpc::ErrorCode::INVALID_PARAMS, "arguments must be an object") unless arguments.is_a?(Hash)
        schema = tool_declaration.input_schema(mcp_server)
        missing = schema.missing_required_arguments(arguments)
        return refuse("Missing required arguments: #{missing.join(", ")}") if missing.any?
        schema.validate_arguments(arguments)
      rescue MCP::Tool::InputSchema::ValidationError => error
        refuse(error.message)
      end

      def permitted_arguments
        tool_declaration.input_schema(mcp_server).to_h.fetch(:properties, {}).map do |name, property|
          case property[:type]
          when "array" then { name => [] }
          when "object" then { name => {} }
          else name
          end
        end
      end

      # Errors Rails answers with a status of its own, such as a rate limit's
      # 429, keep it. Anything else reaches the client only as "Internal error",
      # so its cause has to reach the app's error reporting from here or it is
      # lost.
      def internal_error(exception)
        raise exception if exception.is_a?(ActionController::ActionControllerError)
        ::Rails.error.report(exception, source: "stateless_mcp")
        render_rpc_error(Rpc::ErrorCode::INTERNAL_ERROR, "Internal error")
      end
    end
  end
end
