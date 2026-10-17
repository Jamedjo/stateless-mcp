RSpec.describe StatelessMcp::Cursor do
  it "round-trips its values through an opaque, URL-safe string" do
    cursor = described_class.encode("2026-10-01T09:00:00.000000Z", 42)

    expect(cursor).to match(/\A[A-Za-z0-9_-]+\z/)
    expect(described_class.decode(cursor)).to eq(["2026-10-01T09:00:00.000000Z", 42])
  end

  it "checks how many values a cursor holds" do
    cursor = described_class.encode(1, 2)

    expect(described_class.decode(cursor, count: 2)).to eq([1, 2])
    expect { described_class.decode(cursor, count: 1) }.to raise_error(described_class::Invalid)
  end

  it "refuses a cursor it didn't issue" do
    ["page-2", "", nil, "!!!", Base64.strict_encode64(JSON.generate({ "page" => 2 }))].each do |cursor|
      expect { described_class.decode(cursor) }.to raise_error(described_class::Invalid), "expected #{cursor.inspect} to be refused"
    end
  end
end
