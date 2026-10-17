class Admin::NotesController < Mcp::BaseController
  tool :index, "Lists every note, newest first.", title: "List all notes" do
    paginated "notes"
  end
  def index
    page, next_cursor = paginate_list(Note.all)
    render_tool notes: page.map(&:title), next_cursor: next_cursor
  end

  tool :count, "Counts every note.", title: "Count notes"
  def count
    render_tool count: Note.all.size
  end
end
