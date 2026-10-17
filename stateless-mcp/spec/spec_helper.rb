require "stateless-mcp"
require "rack/test"
require_relative "support/mcp_requests"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = ".rspec_status"
  config.order = :random
end
