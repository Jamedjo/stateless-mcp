class Admin::NotesController < Mcp::BaseController
  tool :index, "Lists every note, newest first.", title: "List all notes" do
    paginated "notes"
  end

  tool :count, "Counts every note.", title: "Count notes"
end
