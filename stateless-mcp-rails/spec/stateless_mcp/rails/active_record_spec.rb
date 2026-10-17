require "stateless_mcp/rails/active_record"

RSpec.describe StatelessMcp::Rails::RecordPagination do
  # An in-memory table of its own, so the dummy app stays free of ActiveRecord.
  before(:all) do
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    ActiveRecord::Schema.verbose = false
    ActiveRecord::Schema.define do
      create_table(:entries) { |table| table.string :title; table.datetime :created_at, precision: 6 }
      create_table(:tokens, id: :string) { |table| table.datetime :created_at, precision: 6 }
    end
  end

  after(:all) { ActiveRecord::Base.remove_connection }

  let(:entry) { Class.new(ActiveRecord::Base) { self.table_name = "entries" } }

  # Stands in for a controller including StatelessMcp::Rails::Controller.
  let(:host_class) do
    Class.new do
      include StatelessMcp::Rails::RecordPagination
      public :paginate

      attr_reader :tool_params

      def initialize(cursor: nil)
        @tool_params = { cursor: cursor }
      end

      def page_limit
        2
      end
    end
  end

  before { entry.delete_all }

  def page(records, cursor: nil, **options)
    host_class.new(cursor: cursor).paginate(records, **options)
  end

  def pages(records)
    rows, cursor = page(records)
    result = [rows]
    while cursor
      rows, cursor = page(records, cursor: cursor)
      result << rows
    end
    result
  end

  it "pages newest first, with next_cursor until the last page" do
    ["Oldest", "Middle", "Newest"].each_with_index { |title, day| entry.create!(title: title, created_at: Time.utc(2026, 10, day + 1)) }

    expect(pages(entry.all).map { |rows| rows.map(&:title) }).to eq([["Newest", "Middle"], ["Oldest"]])
  end

  it "pages through records written at the same moment, by id" do
    moment = Time.utc(2026, 10, 1, 9)
    tied = Array.new(5) { entry.create!(created_at: moment) }

    expect(pages(entry.all).flatten.map(&:id)).to eq(tied.map(&:id).reverse)
  end

  it "keeps a page's place when newer records arrive between calls" do
    3.times { |day| entry.create!(title: "Day #{day}", created_at: Time.utc(2026, 10, day + 1)) }
    first, cursor = page(entry.all)
    entry.create!(title: "Later", created_at: Time.utc(2026, 11, 1))

    second, = page(entry.all, cursor: cursor)

    expect((first + second).map(&:title)).to eq(["Day 2", "Day 1", "Day 0"])
  end

  it "takes a limit other than the call's" do
    3.times { entry.create!(created_at: Time.current) }

    expect(page(entry.all, limit: 3).first.size).to eq(3)
  end

  it "pages records with string keys" do
    token = Class.new(ActiveRecord::Base) { self.table_name = "tokens" }
    ["a", "b", "c"].each { |id| token.create!(id: id, created_at: Time.utc(2026, 10, 1)) }

    expect(pages(token.all).flatten.map(&:id)).to eq(["c", "b", "a"])
  end

  it "refuses a cursor it didn't issue" do
    [StatelessMcp::Cursor.encode("yesterday", 1), StatelessMcp::Cursor.encode("2026-10-01T00:00:00Z", nil), StatelessMcp::Cursor.encode(1)].each do |cursor|
      expect { page(entry.all, cursor: cursor) }.to raise_error(StatelessMcp::Cursor::Invalid)
    end
  end
end
