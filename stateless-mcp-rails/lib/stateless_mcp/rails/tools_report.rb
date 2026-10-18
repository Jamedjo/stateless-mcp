module StatelessMcp
  module Rails
    # The text `rake mcp:tools` prints: each server's tools as a table, with
    # each tool's argument schema on the line below it when verbose.
    class ToolsReport
      HEADINGS = ["Tool", "Title", "Action", "Read-only"].freeze

      def initialize(route_set, verbose: false)
        @route_set = route_set
        @verbose = verbose
      end

      def to_s
        Routing.servers(@route_set).map { |server| server_section(server) }.join("\n")
      end

      private

      def server_section(server)
        tools = Routing.listed_tools(server, @route_set)
        return "#{server.name} (#{server.path})\n  No tools\n" if tools.empty?
        rows = tools.map { |entry, controller, action| row(entry, controller, action) }
        widths = HEADINGS.each_index.map { |column| ([HEADINGS] + rows).map { |cells| cells[column].length }.max }
        lines = [format_row(HEADINGS, widths)]
        rows.zip(tools) do |cells, (entry, _, _)|
          lines << format_row(cells, widths)
          lines << "    #{JSON.generate(entry[:inputSchema].except(:"$schema"))}" if @verbose
        end
        "#{server.name} (#{server.path})\n#{lines.join("\n")}\n"
      end

      def row(entry, controller, action)
        read_only = entry.dig(:annotations, :readOnlyHint)
        [entry[:name], entry[:title].to_s, "#{controller.controller_path}##{action}", read_only.nil? ? "" : (read_only ? "yes" : "no")]
      end

      def format_row(cells, widths)
        "  #{cells.zip(widths).map { |cell, width| cell.ljust(width) }.join("  ")}".rstrip
      end
    end
  end
end
