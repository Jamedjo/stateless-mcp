module StatelessMcp
  # JSON-RPC envelopes, and the HTTP status each error travels with. The
  # envelopes are the mcp gem's own.
  module Rpc
    ErrorCode = JsonRpcHandler::ErrorCode
    BAD_REQUEST_CODES = MCP::Server::Transports::StreamableHTTPTransport::MODERN_BAD_REQUEST_CODES

    def self.success(id, result)
      JsonRpcHandler.success_response(id: id, result: result)
    end

    # A request whose id is missing or malformed is answered with a null id.
    # JSON-RPC 2.0 requires the id in every error response, and mcp 1.9 leaves
    # out one it can't use, so the id is always set here.
    def self.error(id, code, message, data: nil)
      response = JsonRpcHandler.error_response(id: id.nil? ? :unknown_id : id, id_validation_pattern: JsonRpcHandler::DEFAULT_ALLOWED_ID_CHARACTERS, error: { code: code, message: message, data: data })
      { jsonrpc: response[:jsonrpc], id: response[:id], error: response[:error] }
    end

    # A 404 carrying a JSON-RPC body tells a client it reached a current server
    # that lacks the method, rather than a missing endpoint.
    def self.status_for(code)
      return 404 if code == ErrorCode::METHOD_NOT_FOUND
      BAD_REQUEST_CODES.include?(code) ? 400 : 200
    end
  end
end
