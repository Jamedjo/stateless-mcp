# Builds 2026-07-28 requests the way a conforming client sends them.
module McpRequests
  PROTOCOL_VERSION = "2026-07-28"

  def mcp_body(method, params = {}, id: 1)
    meta = { "io.modelcontextprotocol/protocolVersion" => PROTOCOL_VERSION, "io.modelcontextprotocol/clientCapabilities" => {} }
    { jsonrpc: "2.0", id: id, method: method, params: params.merge(_meta: meta) }.compact
  end

  def mcp_headers(method, name = nil)
    headers = { "CONTENT_TYPE" => "application/json", "HTTP_ACCEPT" => "application/json, text/event-stream", "HTTP_MCP_PROTOCOL_VERSION" => PROTOCOL_VERSION, "HTTP_MCP_METHOD" => method }
    headers["HTTP_MCP_NAME"] = name if name
    headers
  end

  def post_mcp(path, method, params = {}, headers: {})
    post path, JSON.generate(mcp_body(method, params)), mcp_headers(method, params[:name]).merge(headers)
  end

  def json_response
    JSON.parse(last_response.body)
  end
end
