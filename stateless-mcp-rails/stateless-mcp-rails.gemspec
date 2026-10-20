require_relative "../stateless-mcp/lib/stateless_mcp/version"

Gem::Specification.new do |spec|
  spec.name = "stateless-mcp-rails"
  spec.version = StatelessMcp::VERSION
  spec.authors = ["James Edwards-Jones"]
  spec.email = ["git@jamedjo.co.uk"]

  spec.summary = "MCP tools as Rails routes and controller actions"
  spec.description = "MCP tools are declared in config/routes.rb with mcp_server and mcp_resource, and each tool is a controller action. tools/list is built from the routes. Arguments are checked against each tool's schema before the action runs. Sign-in and rate limits use the app's own before_action and rate_limit. Built on stateless-mcp, for MCP 2026-07-28."
  spec.homepage = "https://github.com/Jamedjo/stateless-mcp"
  spec.licenses = ["MIT", "Apache-2.0"]
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/Jamedjo/stateless-mcp/tree/v#{spec.version}/stateless-mcp-rails"
  spec.metadata["changelog_uri"] = "https://github.com/Jamedjo/stateless-mcp/blob/main/stateless-mcp-rails/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://github.com/Jamedjo/stateless-mcp/blob/main/README.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/Jamedjo/stateless-mcp/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "app/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE-MIT", "LICENSE-APACHE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "stateless-mcp", StatelessMcp::VERSION
  spec.add_dependency "actionpack", ">= 7.2", "< 9"
  spec.add_dependency "railties", ">= 7.2", "< 9"
end
