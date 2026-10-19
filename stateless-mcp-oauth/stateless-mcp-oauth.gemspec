require_relative "../stateless-mcp/lib/stateless_mcp/version"

Gem::Specification.new do |spec|
  spec.name = "stateless-mcp-oauth"
  spec.version = StatelessMcp::VERSION
  spec.authors = ["James Edwards-Jones"]
  spec.email = ["git@jamedjo.co.uk"]

  spec.summary = "OAuth for MCP servers built with stateless-mcp"
  spec.description = "With OAuth, a person connects an MCP client such as claude.ai to an app by signing in to that app. No API keys are copied. With stateless-mcp-oauth, the app is the OAuth server for its stateless-mcp tools. The app controls how grants and tokens are stored and encrypted, through a subclass of StatelessMcp::OAuth::Storage. Tested examples encrypt tokens with Rails' MessageEncryptor, or store them as rows."
  spec.homepage = "https://github.com/Jamedjo/stateless-mcp"
  spec.licenses = ["MIT", "Apache-2.0"]
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/Jamedjo/stateless-mcp/tree/v#{spec.version}/stateless-mcp-oauth"
  spec.metadata["changelog_uri"] = "https://github.com/Jamedjo/stateless-mcp/blob/main/stateless-mcp-oauth/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://github.com/Jamedjo/stateless-mcp/blob/main/docs/oauth.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/Jamedjo/stateless-mcp/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "test_support/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE-MIT", "LICENSE-APACHE"]
  spec.require_paths = ["lib", "test_support"]

  spec.add_dependency "stateless-mcp", StatelessMcp::VERSION
end
