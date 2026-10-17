module StatelessMcp
  # What a tool says about itself in tools/list: its title, description,
  # behaviour hints and arguments. The name is left to whatever routes calls
  # to the tool, so one declaration can't be listed under two names by mistake.
  #
  #   StatelessMcp::ToolDeclaration.new(title: "List notes", description: "Lists notes, newest first.") do
  #     argument :tag, :string, "Only notes with this tag"
  #     argument :created_after, :datetime, "ISO 8601 date or time"
  #     paginated "notes"
  #   end
  #
  # The arguments are built once per server, because paginated describes that
  # server's page sizes.
  class ToolDeclaration
    READ_ONLY = { read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false }.freeze

    attr_reader :title, :description, :annotations

    def initialize(title:, description:, annotations: READ_ONLY, &arguments)
      @title = title
      @description = description
      @annotations = annotations
      @arguments = arguments
      @input_schemas = {}
      @lock = Mutex.new
    end

    # The JSON Schema the mcp gem validates a call's arguments with.
    def input_schema(server)
      @lock.synchronize { @input_schemas[server] ||= MCP::Tool::InputSchema.new(Arguments.build(server, &@arguments)) }
    end

    # The tools/list entry, built by the mcp gem so its shape keeps up with the spec.
    def to_h(name, server)
      MCP::Tool.define(name: name, title: title, description: description, input_schema: input_schema(server), annotations: annotations).to_h
    end

    # The block a declaration is written in.
    class Arguments
      def self.build(server, &block)
        arguments = new(server)
        arguments.instance_eval(&block) if block
        arguments.to_h
      end

      def initialize(server)
        @server = server
        @properties = {}
        @required = []
      end

      # Types are JSON Schema's, plus :datetime, which travels as a string.
      # Further keywords, such as enum: or minimum:, go into the property as given.
      def argument(name, type, description, required: false, **keywords)
        @properties[name.to_s] = { type: type.to_s == "datetime" ? "string" : type.to_s, description: description, **keywords }
        @required << name.to_s if required
      end

      # limit and cursor, described with the server's page sizes.
      def paginated(noun = "results")
        argument :limit, :integer, "How many #{noun} to return, #{@server.page_size} by default", minimum: 1, maximum: @server.max_page_size
        argument :cursor, :string, "next_cursor from an earlier result, for the next page"
      end

      def to_h
        { properties: @properties, required: (@required unless @required.empty?) }.compact
      end
    end
  end
end
