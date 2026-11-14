RSpec.describe StatelessMcp::OAuth::ClientMetadata do
  let(:client_id) { "https://app.example.com/oauth/client.json" }
  let(:document) { { client_id: client_id, client_name: "Example", redirect_uris: ["https://app.example.com/cb", "http://127.0.0.1:3000/callback"] } }

  def parse(overrides = {})
    described_class.parse(client_id, JSON.generate(document.merge(overrides)))
  end

  it "matches redirect URIs exactly, except for the port of a loopback one" do
    metadata = parse

    expect(metadata.redirect_uri?("https://app.example.com/cb")).to be(true)
    expect(metadata.redirect_uri?("https://app.example.com/cb?x=1")).to be(false)
    expect(metadata.redirect_uri?("https://app.example.com:8443/cb")).to be(false)
    expect(metadata.redirect_uri?("https://APP.example.com/cb")).to be(false)
    expect(metadata.redirect_uri?("http://127.0.0.1:61234/callback")).to be(true)
    expect(metadata.redirect_uri?("http://127.0.0.1:61234/other")).to be(false)
    expect(metadata.redirect_uri?("http://localhost:61234/callback")).to be(false)
    expect(metadata.redirect_uri?(nil)).to be(false)
  end

  it "detects loopback redirect URIs" do
    expect(described_class.loopback?("http://127.0.0.1:3000/cb")).to be(true)
    expect(described_class.loopback?("http://[::1]/cb")).to be(true)
    expect(described_class.loopback?("http://localhost/cb")).to be(true)
    expect(described_class.loopback?("https://127.0.0.1/cb")).to be(false)
    expect(described_class.loopback?("http://app.example.com/cb")).to be(false)
    expect(described_class.loopback?(nil)).to be(false)
  end

  context "with Claude Code's document, which lists localhost and 127.0.0.1" do
    let(:client_id) { "https://claude.ai/oauth/claude-code-client-metadata" }
    let(:document) { { client_id: client_id, client_name: "Claude Code", client_uri: "https://claude.ai", redirect_uris: ["http://localhost/callback", "http://127.0.0.1/callback"], grant_types: ["authorization_code", "refresh_token"], response_types: ["code"], token_endpoint_auth_method: "none" } }

    it "accepts its localhost redirect on any port by default" do
      expect(parse.redirect_uri?("http://localhost:61234/callback")).to be(true)
      expect(parse.redirect_uri?("http://127.0.0.1:61234/callback")).to be(true)
    end

    it "refuses the document with localhost_redirects: false, as RFC 8252 advises" do
      expect { described_class.parse(client_id, JSON.generate(document), localhost_redirects: false) }.to raise_error(StatelessMcp::OAuth::Error, /redirect_uris/)
      only_ips = described_class.parse(client_id, JSON.generate(document.merge(redirect_uris: ["http://127.0.0.1/callback"])), localhost_redirects: false)
      expect(only_ips.redirect_uri?("http://127.0.0.1:61234/callback")).to be(true)
      expect(only_ips.loopback?("http://localhost:61234/callback")).to be(false)
    end
  end

  context "with ChatGPT's document, which prefers private_key_jwt but supports none" do
    let(:client_id) { "https://chatgpt.com/oauth/client.json" }
    let(:document) { { client_id: client_id, client_name: "ChatGPT", redirect_uris: ["https://chatgpt.com/connector_platform_oauth_redirect"], grant_types: ["authorization_code", "refresh_token", "urn:ietf:params:oauth:grant-type:jwt-bearer"], response_types: ["code"], token_endpoint_auth_method: "private_key_jwt", token_endpoint_auth_methods_supported: ["none", "private_key_jwt"] } }

    it "accepts it as a public client" do
      expect(parse.redirect_uri?("https://chatgpt.com/connector_platform_oauth_redirect")).to be(true)
    end
  end

  it "uses client_name as the name, with whitespace collapsed and truncated to 80 characters" do
    expect(parse(client_name: "  Claude\n\t Desktop ").name).to eq("Claude Desktop")
    expect(parse(client_name: "x" * 200).name.length).to eq(80)
    expect(parse.host).to eq("app.example.com")
  end

  it "refuses a document naming another client_id" do
    expect { parse(client_id: "https://app.example.com/other.json") }.to raise_error(StatelessMcp::OAuth::Error, /different client_id/)
  end

  it "refuses redirect URIs that are http to a non-loopback host, have a fragment or credentials, or are missing" do
    ["http://app.example.com/cb", "https://app.example.com/cb#x", "https://user@app.example.com/cb", "app.example.com/cb", 7].each do |uri|
      expect { parse(redirect_uris: [uri]) }.to raise_error(StatelessMcp::OAuth::Error, /redirect_uris/), uri.to_s
    end
    expect { parse(redirect_uris: []) }.to raise_error(StatelessMcp::OAuth::Error, /redirect_uris/)
    expect { parse(redirect_uris: "https://app.example.com/cb") }.to raise_error(StatelessMcp::OAuth::Error, /redirect_uris/)
  end

  it "refuses confidential clients, and clients without the code flow" do
    expect { parse(client_secret: "s") }.to raise_error(StatelessMcp::OAuth::Error, /public clients/)
    expect { parse(token_endpoint_auth_method: "private_key_jwt") }.to raise_error(StatelessMcp::OAuth::Error, /public clients/)
    expect { parse(token_endpoint_auth_methods_supported: ["none", "client_secret_basic"]) }.to raise_error(StatelessMcp::OAuth::Error, /public clients/)
    expect { parse(token_endpoint_auth_methods_supported: ["private_key_jwt"]) }.to raise_error(StatelessMcp::OAuth::Error, /public clients/)
    expect { parse(token_endpoint_auth_method: "client_secret_basic", token_endpoint_auth_methods_supported: ["none"]) }.to raise_error(StatelessMcp::OAuth::Error, /public clients/)
    expect { parse(grant_types: ["client_credentials"]) }.to raise_error(StatelessMcp::OAuth::Error, /authorization code flow/)
    expect { parse(response_types: ["token"]) }.to raise_error(StatelessMcp::OAuth::Error, /authorization code flow/)
  end

  it "refuses documents without a name or that aren't JSON objects, with an error that isn't redirectable" do
    expect { parse(client_name: " ") }.to raise_error(StatelessMcp::OAuth::Error, /client_name/)
    expect { described_class.parse(client_id, "[]") }.to raise_error(StatelessMcp::OAuth::Error, /JSON object/)
    expect { described_class.parse(client_id, "nope") }.to raise_error(an_instance_of(StatelessMcp::OAuth::Error).and(having_attributes(code: "invalid_client", redirectable?: false)))
  end

  describe ".ttl" do
    it "follows max-age within a minute to a day, and caches nothing marked no-store" do
      expect(described_class.ttl("public, max-age=600")).to eq(600)
      expect(described_class.ttl("max-age=1")).to eq(60)
      expect(described_class.ttl("max-age=9999999")).to eq(86_400)
      expect(described_class.ttl(nil)).to eq(300)
      expect(described_class.ttl("no-store")).to be_nil
      expect(described_class.ttl("private, max-age=600")).to be_nil
      expect(described_class.ttl("max-age=0")).to be_nil
    end
  end

  describe ".fetch" do
    let(:body) { JSON.generate(document) }
    let(:cache_control) { "max-age=600" }
    let(:transport) do
      body = self.body
      FakeTransport.new(cache_control: cache_control) { body }
    end
    let(:fetched) { transport.fetched }
    let(:cache) { StatelessMcp::OAuth::MemoryCache.new }

    it "serves a document from the cache until the entry expires" do
      2.times { described_class.fetch(client_id, transport: transport, cache: cache) }

      expect(fetched).to eq([client_id])
    end

    context "marked no-store" do
      let(:cache_control) { "no-store" }

      it "fetches it every time" do
        2.times { described_class.fetch(client_id, transport: transport, cache: cache) }

        expect(fetched.size).to eq(2)
      end
    end

    context "that fails the checks" do
      let(:body) { JSON.generate(document.merge(client_id: "https://app.example.com/other.json")) }

      it "never caches it" do
        2.times { expect { described_class.fetch(client_id, transport: transport, cache: cache) }.to raise_error(StatelessMcp::OAuth::Error) }

        expect(fetched.size).to eq(2)
      end
    end

    it "checks the client_id before fetching anything" do
      expect { described_class.fetch("http://app.example.com/oauth/client.json", transport: transport, cache: cache) }.to raise_error(StatelessMcp::OAuth::Error, /https URL/)
      expect(fetched).to be_empty
    end

    it "refuses a client whose document can't be fetched" do
      missing = FakeTransport.new { nil }

      expect { described_class.fetch(client_id, transport: missing, cache: cache) }.to raise_error(StatelessMcp::OAuth::Error, "Couldn't load the client's metadata document from app.example.com")
    end
  end
end

RSpec.describe StatelessMcp::OAuth::ClientId do
  it "takes an https URL with a path" do
    expect(described_class.check!("https://claude.ai/oauth/mcp-oauth-client-metadata")).to eq("https://claude.ai/oauth/mcp-oauth-client-metadata")
  end

  it "refuses anything else, with an error that isn't redirectable" do
    ["http://claude.ai/doc", "https://claude.ai", "https://claude.ai/", "https://user:pass@claude.ai/doc", "https://claude.ai/doc#x", "https://claude.ai:8443/doc", "https://claude.ai:443/doc", "https://claude.ai/a/../doc", "https://claude.ai/./doc", "claude.ai/doc", "https://claude.ai/#{"a" * 255}", nil, ["https://claude.ai/doc"]].each do |client_id|
      expect { described_class.check!(client_id) }.to raise_error(an_instance_of(StatelessMcp::OAuth::Error).and(having_attributes(code: "invalid_client", redirectable?: false))), client_id.inspect
    end
  end
end

RSpec.describe StatelessMcp::OAuth::MemoryCache do
  it "drops expired entries, and the oldest entry when full" do
    cache = described_class.new(max_entries: 2)
    cache.write("a", "1", expires_in: 60)
    cache.write("b", "2", expires_in: 0)
    expect([cache.read("a"), cache.read("b")]).to eq(["1", nil])

    cache.write("c", "3", expires_in: 60)
    cache.write("d", "4", expires_in: 60)
    expect([cache.read("a"), cache.read("c"), cache.read("d")]).to eq([nil, "3", "4"])
  end
end
