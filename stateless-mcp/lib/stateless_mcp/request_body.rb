module StatelessMcp
  # Reads and parses a request's JSON-RPC body, refusing it before reading
  # past max_bytes. The body is put back as a fresh input, so the app can read
  # it again as it would any other request.
  module RequestBody
    def self.read(env, max_bytes:)
      raise too_large(max_bytes) if env["CONTENT_LENGTH"].to_i > max_bytes
      raw = env["rack.input"]&.read(max_bytes + 1).to_s
      raise too_large(max_bytes) if raw.bytesize > max_bytes
      env["rack.input"] = StringIO.new(raw)
      body = JSON.parse(raw)
      raise Refusal.new(Rpc::ErrorCode::INVALID_REQUEST, "Body must be a single JSON-RPC request object") unless single_request?(body)
      body
    rescue JSON::ParserError
      raise Refusal.new(Rpc::ErrorCode::PARSE_ERROR, "Parse error")
    end

    # Batches are refused: 2026-07-28 carries one message per POST.
    def self.single_request?(body)
      body.is_a?(Hash) && JsonRpcHandler.valid_version?(body["jsonrpc"]) && JsonRpcHandler.valid_method_name?(body["method"])
    end

    def self.too_large(max_bytes)
      Refusal.new(Rpc::ErrorCode::INVALID_REQUEST, "Request body is larger than #{max_bytes} bytes")
    end

    private_class_method :single_request?, :too_large
  end
end
