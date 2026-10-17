class Mcp::NotesController < Mcp::BaseController
  # Small, so a spec can page through a body in a few parts.
  BODY_PART = 10

  tool :index, "Lists notes, newest first.", title: "List notes" do
    argument :tag, :string, "Only notes with this tag"
    argument :created_after, :datetime, "ISO 8601 date or time; only notes written at or after it"
    paginated "notes"
  end
  def index
    notes = Note.all
    notes = notes.select { |note| note.tags.include?(tool_params[:tag]) } if tool_params[:tag].present?
    created_after = tool_time(:created_after)
    notes = notes.select { |note| note.created_at >= created_after } if created_after
    page, next_cursor = paginate_list(notes)
    render_tool notes: page.map { |note| note_json(note) }, next_cursor: next_cursor
  end

  tool :show, "Gets one note's title and tags. Its text comes from get_note_body.", title: "Get a note" do
    argument :note_id, :integer, "The note id from list_notes", required: true
  end
  def show
    render_tool note_json(note)
  end

  tool :body, "Gets a note's text. Long notes come in parts: call again with next_cursor until it is absent.", title: "Get a note's text" do
    argument :note_id, :integer, "The note id from list_notes", required: true
    argument :cursor, :string, "next_cursor from an earlier result, for the next part"
  end
  def body
    part, next_cursor = paginate_text(BODY_PART) { |start, length| note.body[start, length] }
    render_tool id: note.id, body: part, next_cursor: next_cursor
  end

  private

  def note
    @note ||= Note.find(tool_params[:note_id]) or raise StatelessMcp::InvalidArgument, "No note #{tool_params[:note_id]}"
  end

  def note_json(note)
    { id: note.id, title: note.title, tags: note.tags, created_at: note.created_at.iso8601 }
  end
end
