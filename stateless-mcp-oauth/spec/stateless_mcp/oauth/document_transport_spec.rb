require "webmock/rspec"

RSpec.describe StatelessMcp::OAuth::DocumentTransport do
  let(:url) { "https://claude.ai/oauth/mcp-oauth-client-metadata" }
  let(:addresses) { { "claude.ai" => ["160.79.104.10"] } }
  let(:resolver) do
    addresses = self.addresses
    ->(host, _timeout) { addresses.fetch(host, []).map { |address| IPAddr.new(address) } }
  end
  let(:json) { { "Content-Type" => "application/json" } }

  def fetch(transport = described_class.new(resolver: resolver), at: url)
    StatelessMcp::OAuth::DocumentFetcher.new(transport).get(at)
  end

  it "fetches the document from a public address" do
    stub_request(:get, url).with(headers: { "Accept" => "application/json", "Accept-Encoding" => "identity" }).to_return(status: 200, body: "{}", headers: json.merge("Cache-Control" => "max-age=60"))

    expect(fetch).to eq(["{}", "max-age=60"])
  end

  it "refuses a host with only private addresses, without connecting" do
    ["10.0.0.5", "127.0.0.1", "169.254.169.254", "::1", "::ffff:10.0.0.1", "fd00::1"].each do |address|
      addresses["sneaky.example"] = [address]
      sneaky = stub_request(:get, "https://sneaky.example/client.json")

      expect { fetch(at: "https://sneaky.example/client.json") }.to raise_error(StatelessMcp::OAuth::DocumentFetcher::Failed, /no public ip/), address
      expect(sneaky).not_to have_been_requested
    end
  end

  it "refuses the app's own deny_networks too" do
    addresses["claude.ai"] = ["100.64.1.2"]
    stub_request(:get, url)

    expect { fetch(described_class.new(deny_networks: ["100.64.0.0/10"], resolver: resolver)) }.to raise_error(StatelessMcp::OAuth::DocumentFetcher::Failed, /denied addresses/)
  end

  it "refuses a host that doesn't resolve" do
    expect { fetch(at: "https://nowhere.example/client.json") }.to raise_error(StatelessMcp::OAuth::DocumentFetcher::Failed, /resolve/)
  end

  it "never follows a redirect" do
    target = stub_request(:get, "https://claude.ai/elsewhere")
    stub_request(:get, url).to_return(status: 302, headers: { "Location" => "https://claude.ai/elsewhere" })

    expect { fetch }.to raise_error(StatelessMcp::OAuth::DocumentFetcher::Failed, /302/)
    expect(target).not_to have_been_requested
  end

  it "refuses a host that doesn't answer in time" do
    stub_request(:get, url).to_timeout

    expect { fetch }.to raise_error(StatelessMcp::OAuth::DocumentFetcher::Failed)
  end

  it "sends the app's headers, but not in place of the fetch's own" do
    stub_request(:get, url).with(headers: { "User-Agent" => "Notes", "Accept" => "application/json" }).to_return(status: 200, body: "{}", headers: json)

    expect(fetch(described_class.new(headers: { "User-Agent" => "Notes", "Accept" => "*/*" }, resolver: resolver)).first).to eq("{}")
  end

  it "sends the fetch through a proxy, which resolves the host itself" do
    stub_request(:get, url).to_return(status: 200, body: "{}", headers: json)
    allow(Net::HTTP).to receive(:start).and_call_original

    fetch(described_class.new(proxy: "http://smokescreen.internal:4750"), at: url)

    expect(Net::HTTP).to have_received(:start).with("claude.ai", 443, "smokescreen.internal", 4750, nil, nil, hash_including(use_ssl: true))
  end

  it "refuses deny_networks with a proxy, since the proxy resolves the host" do
    expect { described_class.new(proxy: "http://smokescreen.internal:4750", deny_networks: ["100.64.0.0/10"]) }.to raise_error(ArgumentError, /proxy/)
  end
end
