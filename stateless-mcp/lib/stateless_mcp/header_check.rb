module StatelessMcp
  # 2026-07-28 clients mirror the method and its target into Mcp-Method and
  # Mcp-Name for intermediaries to route on, and the spec requires refusing any
  # request whose headers disagree with its body: otherwise a proxy could log
  # one method while the server runs another.
  module HeaderCheck
    # Raises a Refusal for the first disagreement. A base64-wrapped Mcp-Name is
    # decoded in env, so routes match the name itself.
    def self.check!(env, body)
      check_version(env["HTTP_MCP_PROTOCOL_VERSION"])
      must_match("Mcp-Method", env["HTTP_MCP_METHOD"], body["method"])
      env["HTTP_MCP_NAME"] = decode(env["HTTP_MCP_NAME"]) if env["HTTP_MCP_NAME"]
      target = StatelessMcp.target_name(body)
      must_match("Mcp-Name", env["HTTP_MCP_NAME"], target) if target
      check_envelope(env, body) unless MCP::Methods.notification?(body["method"])
    end

    # Header values outside plain ASCII arrive base64 encoded inside a
    # =?base64?…?= wrapper.
    def self.decode(value)
      encoded = value.to_s[/\A=\?base64\?(.*)\?=\z/m, 1]
      encoded ? Base64.strict_decode64(encoded).force_encoding(Encoding::UTF_8) : value
    rescue ArgumentError
      value
    end

    # A missing header is a mismatch; a version this server doesn't speak is
    # answered with the versions it does.
    def self.check_version(version)
      raise header_mismatch("MCP-Protocol-Version header is required") if version.to_s.empty?
      return if MCP::Configuration.modern_protocol_version?(version)
      raise Refusal.new(MCP::ErrorCodes::UNSUPPORTED_PROTOCOL_VERSION, "Unsupported protocol version", data: { supported: MCP::Configuration::SUPPORTED_MODERN_PROTOCOL_VERSIONS, requested: version })
    end

    def self.check_envelope(env, body)
      must_match("MCP-Protocol-Version", env["HTTP_MCP_PROTOCOL_VERSION"], body.dig("params", "_meta", MCP::RequestEnvelope::PROTOCOL_VERSION_META_KEY)) if MCP::RequestEnvelope.modern?(body["params"])
      MCP::RequestEnvelope.parse!(body["params"])
    rescue MCP::Server::RequestHandlerError => error
      raise Refusal.new(error.error_code, error.message, data: error.error_data)
    end

    def self.must_match(header, sent, expected)
      return if sent == expected
      raise header_mismatch(sent.to_s.empty? ? "#{header} header is required" : "#{header} header value '#{sent}' does not match body value '#{expected}'")
    end

    def self.header_mismatch(detail)
      Refusal.new(MCP::ErrorCodes::HEADER_MISMATCH, "Header mismatch: #{detail}")
    end

    private_class_method :check_version, :check_envelope, :must_match, :header_mismatch
  end
end
