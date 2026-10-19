require "stateless_mcp/oauth/storage_check"

# An RSpec example for each storage check. The example group defines storage
# and approved_by:
#
#   RSpec.describe McpOAuthStorage do
#     it_behaves_like "stateless-mcp oauth storage" do
#       let(:storage) { McpOAuthStorage.new }
#       let(:approved_by) { { user_id: 42 } }
#     end
#   end
RSpec.shared_examples "stateless-mcp oauth storage" do
  StatelessMcp::OAuth::StorageCheck::CHECKS.each do |name, description|
    it description do
      StatelessMcp::OAuth::StorageCheck.new(storage, approved_by: approved_by).run(name)
    rescue StatelessMcp::OAuth::StorageCheck::Failure => failure
      RSpec::Expectations.fail_with(failure.message)
    end
  end
end
