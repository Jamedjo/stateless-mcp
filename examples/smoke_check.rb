# Boots an example's config.ru and makes the calls a client makes: tools/list,
# then tools/call. Also checks that the example's guide in docs/ quotes its
# code exactly. Run from an example's directory with `bundle exec ruby smoke.rb`.
require "json"
require "rack"

module SmokeCheck
  PROTOCOL_VERSION = "2026-07-28"

  def self.run(dir, guide:)
    app = Rack::Builder.parse_file(File.join(dir, "config.ru"))

    status, body = post(app, "tools/list")
    check("tools/list lists get_note", status == 200 && body.dig("result", "tools", 0, "name") == "get_note")

    status, body = post(app, "tools/call", { name: "get_note", arguments: { note_id: 1 } })
    check("tools/call returns the note", status == 200 && body.dig("result", "content", 0, "text") == '{"id":1,"text":"Buy milk"}')

    status, body = post(app, "tools/call", { name: "get_note", arguments: { note_id: 9 } })
    check("tools/call refuses a missing note", status == 200 && body.dig("result", "isError") == true)

    status, body = post(app, "tools/call", { name: "get_note", arguments: { note_id: "one" } })
    check("tools/call refuses a mistyped argument", status == 200 && body.dig("result", "isError") == true)

    status, body = post(app, "resources/list")
    check("an unknown method gets a 404", status == 404 && body.dig("error", "code") == -32601)

    status, = post(app, "tools/list", headers: { "HTTP_ORIGIN" => "https://elsewhere.example" })
    check("another site's page gets a 403", status == 403)

    (Dir[File.join(dir, "*.{rb,ru}")] - [File.join(dir, "smoke.rb")]).each do |file|
      check("#{guide} quotes #{File.basename(file)}", File.read(File.expand_path("../docs/#{guide}", __dir__)).include?("```ruby\n#{File.read(file)}```"))
    end
  end

  def self.post(app, method, params = {}, headers: {})
    meta = { "io.modelcontextprotocol/protocolVersion" => PROTOCOL_VERSION, "io.modelcontextprotocol/clientCapabilities" => {} }
    body = { jsonrpc: "2.0", id: 1, method: method, params: params.merge(_meta: meta) }
    headers = headers.merge("CONTENT_TYPE" => "application/json", "HTTP_MCP_PROTOCOL_VERSION" => PROTOCOL_VERSION, "HTTP_MCP_METHOD" => method)
    headers["HTTP_MCP_NAME"] = params[:name] if params[:name]
    response = Rack::MockRequest.new(app).post("http://localhost/mcp", headers.merge(input: JSON.generate(body)))
    [response.status, JSON.parse(response.body)]
  end

  def self.check(label, passed)
    abort "not ok: #{label}" unless passed
    puts "ok: #{label}"
  end
end
