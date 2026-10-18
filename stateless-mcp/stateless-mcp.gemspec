require_relative "lib/stateless_mcp/version"

Gem::Specification.new do |spec|
  spec.name = "stateless-mcp"
  spec.version = StatelessMcp::VERSION
  spec.authors = ["James Edwards-Jones"]
  spec.email = ["git@jamedjo.co.uk"]

  spec.summary = "Stateless Model Context Protocol servers over plain HTTP, for any Rack app"
  spec.description = "Serves the 2026-07-28 Model Context Protocol without sessions: every request is answered on its own, so any instance behind a load balancer can take any call. Rack middleware, JSON-RPC errors, cursors and tool schemas, with Rails support in stateless-mcp-rails."
  spec.homepage = "https://github.com/Jamedjo/stateless-mcp"
  spec.licenses = ["MIT", "Apache-2.0"]
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/Jamedjo/stateless-mcp"
  spec.metadata["changelog_uri"] = "https://github.com/Jamedjo/stateless-mcp/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://github.com/Jamedjo/stateless-mcp/blob/main/README.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE-MIT", "LICENSE-APACHE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "base64", ">= 0.2", "< 1"
  spec.add_dependency "mcp", ">= 1.8", "< 2"
  spec.add_dependency "rack", ">= 2.2", "< 4"
end
