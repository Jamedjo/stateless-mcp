class Mcp::NotesController < Mcp::BaseController
  tool :index, "Lists notes, newest first.", title: "List notes" do
    argument :tag, :string, "Only notes with this tag"
    argument :created_after, :datetime, "ISO 8601 date or time; only notes written at or after it"
    paginated "notes"
  end

  tool :show, "Gets one note's title and tags. Its text comes from get_note_body.", title: "Get a note" do
    argument :note_id, :integer, "The note id from list_notes", required: true
  end

  tool :body, "Gets a note's text. Long notes come in parts: call again with next_cursor until it is absent.", title: "Get a note's text" do
    argument :note_id, :integer, "The note id from list_notes", required: true
    argument :cursor, :string, "next_cursor from an earlier result, for the next part"
  end
end
