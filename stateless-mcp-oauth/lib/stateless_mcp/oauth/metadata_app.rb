require "json"

module StatelessMcp
  module OAuth
    # A Rack app serving one metadata document, which clients read before they
    # sign in. Clients in a browser read it from another origin, and send an
    # MCP-Protocol-Version header with it, so it answers a CORS preflight too.
    # The document holds nothing private, so any origin may read it.
    class MetadataApp
      HEADERS = { "content-type" => "application/json", "cache-control" => "public, max-age=3600", "access-control-allow-origin" => "*" }.freeze
      PREFLIGHT_HEADERS = { "access-control-allow-origin" => "*", "access-control-allow-methods" => "GET, HEAD, OPTIONS", "access-control-allow-headers" => "*", "access-control-max-age" => "86400" }.freeze

      def initialize(document)
        @body = JSON.generate(document).freeze
      end

      def call(env)
        case env["REQUEST_METHOD"]
        when "GET" then [200, HEADERS.dup, [@body]]
        when "HEAD" then [200, HEADERS.dup, []]
        when "OPTIONS" then [204, PREFLIGHT_HEADERS.dup, []]
        else [405, { "allow" => "GET, HEAD, OPTIONS" }, []]
        end
      end
    end
  end
end
