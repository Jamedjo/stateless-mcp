ENV["RAILS_ENV"] = "test"
require_relative "dummy/config/application"
Dummy::Application.initialize!

require "rack/test"
require_relative "../../stateless-mcp/spec/support/mcp_requests"

# Requests against the dummy app, which serves a default server at /mcp and
# Dummy::ADMIN_MCP at /admin/mcp.
module DummyRequests
  include Rack::Test::Methods
  include McpRequests

  def app
    Rails.application
  end

  def call_mcp(method, params = {}, path: "/mcp", headers: {})
    post_mcp(path, method, params, headers: headers)
    json_response
  end
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = ".rspec_status"
  config.order = :random
  config.include DummyRequests, type: :request
end
