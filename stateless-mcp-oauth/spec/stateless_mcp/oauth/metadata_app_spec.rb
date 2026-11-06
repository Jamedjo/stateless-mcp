require "rack/test"

RSpec.describe StatelessMcp::OAuth::MetadataApp do
  include Rack::Test::Methods

  def app
    Rack::Lint.new(described_class.new(resource: "https://notes.example/mcp"))
  end

  it "serves the document to any origin, cached for an hour" do
    get "/.well-known/oauth-protected-resource/mcp"

    expect(JSON.parse(last_response.body)).to eq("resource" => "https://notes.example/mcp")
    expect(last_response.headers.to_h).to include("access-control-allow-origin" => "*", "cache-control" => "public, max-age=3600")
  end

  it "answers the CORS preflight a browser sends before a request with an MCP-Protocol-Version header" do
    options "/.well-known/oauth-protected-resource/mcp", {}, "HTTP_ORIGIN" => "https://inspector.example", "HTTP_ACCESS_CONTROL_REQUEST_HEADERS" => "mcp-protocol-version"

    expect(last_response.status).to eq(204)
    expect(last_response.headers.to_h).to include("access-control-allow-origin" => "*", "access-control-allow-headers" => "*")
  end

  it "answers HEAD without a body, and refuses anything else" do
    head "/.well-known/oauth-protected-resource/mcp"
    expect([last_response.status, last_response.body]).to eq([200, ""])

    post "/.well-known/oauth-protected-resource/mcp"
    expect(last_response.status).to eq(405)
  end
end
