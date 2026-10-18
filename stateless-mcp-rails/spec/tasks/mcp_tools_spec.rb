require "rake"

RSpec.describe "rake mcp:tools" do
  # A Rake application of its own, so the tasks load once per example and no
  # other spec sees them.
  around do |example|
    original = Rake.application
    Rake.application = Rake::Application.new
    Rails.application.load_tasks
    example.run
  ensure
    Rake.application = original
  end

  def output_of(verbose: false)
    ENV["VERBOSE"] = "1" if verbose
    captured = StringIO.new
    original, $stdout = $stdout, captured
    Rake::Task["mcp:tools"].invoke
    captured.string
  ensure
    $stdout = original
    ENV.delete("VERBOSE")
  end

  it "lists each server's tools with their titles, actions and read-only hints" do
    expect(output_of).to eq(<<~TEXT)
      notes (/mcp)
        Tool           Title              Action           Read-only
        list_notes     List notes         mcp/notes#index  yes
        get_note       Get a note         mcp/notes#show   yes
        get_note_body  Get a note's text  mcp/notes#body   yes

      admin (/admin/mcp)
        Tool         Title           Action             Read-only
        list_notes   List all notes  admin/notes#index  yes
        count_notes  Count notes     admin/notes#count  yes
    TEXT
  end

  it "adds each tool's argument schema with VERBOSE=1" do
    lines = output_of(verbose: true).lines.map(&:strip)

    expect(lines[lines.index { |line| line.start_with?("get_note ") } + 1]).to eq('{"properties":{"note_id":{"type":"integer","description":"The note id from list_notes"}},"required":["note_id"],"type":"object"}')
    expect(lines[lines.index { |line| line.start_with?("count_notes") } + 1]).to eq('{"properties":{},"type":"object"}')
  end

  it "lists the same tools as tools/list", type: :request do
    rake_names = output_of.lines.grep(/#/).map { |line| line.split.first }
    listed_names = ["/mcp", "/admin/mcp"].flat_map { |path| call_mcp("tools/list", path: path).dig("result", "tools").map { |tool| tool["name"] } }

    expect(rake_names).to eq(listed_names)
  end
end
