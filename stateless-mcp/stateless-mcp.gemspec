require_relative "lib/stateless_mcp/version"

Gem::Specification.new do |spec|
  spec.name = "stateless-mcp"
  spec.version = StatelessMcp::VERSION
  spec.authors = ["James Edwards-Jones"]
  spec.email = ["git@jamedjo.co.uk"]

  spec.summary = "MCP servers routed like REST APIs, built for MCP 2026-07-28"
  spec.description = "In MCP 2026-07-28, every request has Mcp-Method and Mcp-Name headers, and there are no sessions. stateless-mcp is built on those headers from the ground up. MCP tools are routed like REST endpoints in the app's Rack or Sinatra stack, instead of in a separate session-based server. The gem provides the request checks, JSON-RPC errors, tool schemas and cursor paging. Rails apps use stateless-mcp-rails."
  spec.homepage = "https://github.com/Jamedjo/stateless-mcp"
  spec.licenses = ["MIT", "Apache-2.0"]
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/Jamedjo/stateless-mcp/tree/v#{spec.version}/stateless-mcp"
  spec.metadata["changelog_uri"] = "https://github.com/Jamedjo/stateless-mcp/blob/main/stateless-mcp/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://github.com/Jamedjo/stateless-mcp/blob/main/README.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/Jamedjo/stateless-mcp/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE-MIT", "LICENSE-APACHE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "base64", ">= 0.2", "< 1"
  spec.add_dependency "mcp", ">= 1.8", "< 2"
  spec.add_dependency "rack", ">= 2.2", "< 4"
end
