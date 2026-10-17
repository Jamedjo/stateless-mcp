module StatelessMcp
  # The result objects a server answers with, before they are wrapped in a
  # JSON-RPC response.
  module Result
    # Every 2026-07-28 result names its type. A cacheable one also carries the
    # spec's cache hints, set so a client caches it only for this caller and
    # checks again before reusing it.
    def self.complete(result, cacheable: false)
      result = { ttlMs: 0, cacheScope: "private" }.merge(result) if cacheable
      result.merge(resultType: MCP::ResultType::COMPLETE)
    end

    # A tool's answer, as JSON in one text block, leaving out a hash's nil
    # values. Clients hand the text to the model. structuredContent is for
    # programs validating against an outputSchema, which these tools don't
    # declare, so sending it as well would only double every result.
    def self.tool(payload)
      payload = payload.compact if payload.is_a?(Hash)
      complete(MCP::Tool::Response.new([{ type: "text", text: payload.to_json }]).to_h)
    end

    # A tool call turned down with a message the model can read and act on.
    def self.refusal(message)
      complete(MCP::Tool::Response.new([{ type: "text", text: message }], error: true).to_h)
    end

    # The answer to server/discover.
    def self.discover(server, capabilities:)
      complete({ supportedVersions: MCP::Configuration::SUPPORTED_MODERN_PROTOCOL_VERSIONS, capabilities: capabilities, instructions: server.instructions, _meta: { MCP::RequestEnvelope::SERVER_INFO_META_KEY => server.info } }.compact, cacheable: true)
    end
  end
end
