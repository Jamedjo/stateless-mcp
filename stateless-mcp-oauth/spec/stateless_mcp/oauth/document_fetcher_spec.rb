RSpec.describe StatelessMcp::OAuth::DocumentFetcher do
  let(:url) { "https://claude.ai/oauth/mcp-oauth-client-metadata" }
  let(:json) { { "content-type" => "application/json" } }

  # A transport that answers with this status, these headers and these chunks.
  def answering(status, response_headers, chunks = ["{}"])
    ->(_url, headers:, timeout:, &block) { block.call(status, response_headers, chunks) }
  end

  def get(transport)
    described_class.new(transport).get(url)
  end

  it "returns the body and its Cache-Control header" do
    expect(get(answering(200, json.merge("cache-control" => "max-age=60")))).to eq(["{}", "max-age=60"])
  end

  it "asks for JSON with no compression, whatever headers the transport adds" do
    asked = nil
    transport = ->(_url, headers:, timeout:, &block) { (asked = headers) && block.call(200, json, ["{}"]) }

    get(transport)

    expect(asked).to eq("accept" => "application/json", "accept-encoding" => "identity")
  end

  it "refuses any status but 200, so a redirect is never followed" do
    [302, 404, 500].each do |status|
      expect { get(answering(status, json.merge("location" => "https://169.254.169.254/"))) }.to raise_error(described_class::Failed, /status #{status}/)
    end
  end

  it "refuses a document not served as JSON, whatever its body" do
    expect(get(answering(200, "content-type" => "application/json; charset=utf-8")).first).to eq("{}")

    [{ "content-type" => "text/html" }, { "content-type" => "text/plain; charset=utf-8" }, {}].each do |headers|
      expect { get(answering(200, headers)) }.to raise_error(described_class::Failed, /not served as JSON/), headers.inspect
    end
  end

  it "refuses a compressed body before reading it" do
    expect { get(answering(200, json.merge("content-encoding" => "gzip"), ["\x1F\x8B".b])) }.to raise_error(described_class::Failed, /compressed as gzip/)
  end

  it "refuses a body past the limit, by its length or as it arrives" do
    stub_const("#{described_class}::MAX_BYTES", 100)

    expect { get(answering(200, json.merge("content-length" => "101"))) }.to raise_error(described_class::Failed, /larger than 100 bytes/)
    expect { get(answering(200, json, ["a" * 60, "a" * 60])) }.to raise_error(described_class::Failed, /larger than 100 bytes/)
  end

  it "times out a slow response, even when each chunk arrives in time" do
    stub_const("#{described_class}::TIMEOUT", 0.1)
    slow = Enumerator.new { |chunks| 5.times { sleep 0.05 and chunks << "{" } }

    expect { get(answering(200, json, slow)) }.to raise_error(described_class::Failed, /slower than 0.1 seconds/)
  end

  it "refuses a URL that isn't https before the transport sees it, and a transport that never answers" do
    expect { described_class.new(answering(200, json)).get("http://claude.ai/client.json") }.to raise_error(described_class::Failed, /https/)
    expect { get(->(_url, headers:, timeout:) { nil }) }.to raise_error(described_class::Failed, /no response/)
  end
end
