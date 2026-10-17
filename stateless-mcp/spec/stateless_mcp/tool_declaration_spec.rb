RSpec.describe StatelessMcp::ToolDeclaration do
  let(:server) { StatelessMcp::Server.new(page_size: 10, max_page_size: 50) }

  let(:declaration) do
    described_class.new(title: "List notes", description: "Lists notes, newest first.") do
      argument :tag, :string, "Only notes with this tag", enum: ["work", "home"]
      argument :created_after, :datetime, "ISO 8601 date or time"
      argument :note_id, :string, "A note id", required: true
      paginated "notes"
    end
  end

  it "builds the tools/list entry through the mcp gem" do
    entry = declaration.to_h("list_notes", server)

    expect(entry).to include(name: "list_notes", title: "List notes", description: "Lists notes, newest first.")
    expect(entry[:annotations]).to eq(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
  end

  it "builds a JSON Schema from the arguments" do
    schema = declaration.input_schema(server).to_h

    expect(schema).to include(type: "object", required: ["note_id"])
    expect(schema[:properties][:tag]).to eq(type: "string", description: "Only notes with this tag", enum: ["work", "home"])
  end

  it "sends a datetime as a string" do
    expect(declaration.input_schema(server).to_h.dig(:properties, :created_after, :type)).to eq("string")
  end

  it "describes paging with the server's own page sizes" do
    other = StatelessMcp::Server.new(page_size: 1, max_page_size: 2)

    expect(declaration.input_schema(server).to_h.dig(:properties, :limit)).to include(description: "How many notes to return, 10 by default", maximum: 50)
    expect(declaration.input_schema(other).to_h.dig(:properties, :limit)).to include(description: "How many notes to return, 1 by default", maximum: 2)
    expect(declaration.input_schema(server).to_h[:properties]).to include(:cursor)
  end

  it "builds each server's schema once" do
    expect(declaration.input_schema(server)).to be(declaration.input_schema(server))
  end

  it "leaves required out when nothing is" do
    schema = described_class.new(title: "Count", description: "Counts notes.").input_schema(server).to_h

    expect(schema).not_to have_key(:required)
    expect(schema[:type]).to eq("object")
  end

  it "takes other annotations for a tool that writes" do
    declaration = described_class.new(title: "Delete a note", description: "Deletes a note.", annotations: { read_only_hint: false, destructive_hint: true })

    expect(declaration.to_h("delete_note", server)[:annotations]).to include(readOnlyHint: false, destructiveHint: true)
  end
end
