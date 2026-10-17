RSpec.describe StatelessMcp::Pagination do
  let(:server) { StatelessMcp::Server.new(page_size: 2, max_page_size: 5) }

  describe ".limit" do
    it "takes the server's page size when a call gives none" do
      expect(described_class.limit(nil, server)).to eq(2)
      expect(described_class.limit("", server)).to eq(2)
    end

    it "holds a requested size to the server's limits" do
      expect(described_class.limit(4, server)).to eq(4)
      expect(described_class.limit("50", server)).to eq(5)
      expect(described_class.limit(0, server)).to eq(1)
    end
  end

  describe ".list" do
    let(:items) { ("a".."e").to_a }

    it "pages through a list with next_cursor" do
      first, cursor = described_class.list(items, cursor: nil, limit: 2)
      second, cursor = described_class.list(items, cursor: cursor, limit: 2)
      third, last_cursor = described_class.list(items, cursor: cursor, limit: 2)

      expect(first + second + third).to eq(items)
      expect(last_cursor).to be_nil
    end

    it "gives no next_cursor when the page is the last" do
      expect(described_class.list(items, cursor: nil, limit: 5)).to eq([items, nil])
    end

    it "gives an empty page past the end" do
      expect(described_class.list(items, cursor: StatelessMcp::Cursor.encode(10), limit: 2)).to eq([[], nil])
    end
  end

  describe ".text" do
    let(:text) { "abcdefg" }

    it "reads a text in parts, asking only for the slice it needs" do
      reads = []
      read = ->(start, length) { reads << [start, length]; text[start, length] }

      first, cursor = described_class.text(nil, 3, &read)
      second, cursor = described_class.text(cursor, 3, &read)
      third, last_cursor = described_class.text(cursor, 3, &read)

      expect(first + second + third).to eq(text)
      expect(last_cursor).to be_nil
      expect(reads).to eq([[0, 4], [3, 4], [6, 4]])
    end
  end

  describe ".offset" do
    it "refuses a cursor that isn't one position" do
      [StatelessMcp::Cursor.encode(1, 2), StatelessMcp::Cursor.encode(-1), StatelessMcp::Cursor.encode("3"), "page-2"].each do |cursor|
        expect { described_class.offset(cursor) }.to raise_error(StatelessMcp::Cursor::Invalid)
      end
    end
  end
end
