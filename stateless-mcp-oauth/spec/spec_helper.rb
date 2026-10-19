require "stateless-mcp-oauth"
require "stateless_mcp/oauth/storage_check/rspec"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = ".rspec_status"
  config.order = :random
end
