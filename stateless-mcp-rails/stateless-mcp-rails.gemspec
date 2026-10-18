require_relative "../stateless-mcp/lib/stateless_mcp/version"

Gem::Specification.new do |spec|
  spec.name = "stateless-mcp-rails"
  spec.version = StatelessMcp::VERSION
  spec.authors = ["James Edwards-Jones"]
  spec.email = ["git@jamedjo.co.uk"]

  spec.summary = "Model Context Protocol tools as ordinary Rails routes and controller actions"
  spec.description = "Rails support for stateless-mcp: a tool is a controller action, routed by the Mcp-Method and Mcp-Name headers of the 2026-07-28 Model Context Protocol, and tools/list is drawn from the routes."
  spec.homepage = "https://github.com/Jamedjo/stateless-mcp"
  spec.licenses = ["MIT", "Apache-2.0"]
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/Jamedjo/stateless-mcp"
  spec.metadata["changelog_uri"] = "https://github.com/Jamedjo/stateless-mcp/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://github.com/Jamedjo/stateless-mcp/blob/main/README.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "app/**/*.rb", "README.md", "LICENSE-MIT", "LICENSE-APACHE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "stateless-mcp", StatelessMcp::VERSION
  spec.add_dependency "actionpack", ">= 7.1", "< 9"
  spec.add_dependency "railties", ">= 7.1", "< 9"
end
