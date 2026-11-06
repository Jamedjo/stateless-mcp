require_relative "../../support/memory_storage"

RSpec.describe MemoryStorage do
  it_behaves_like "stateless-mcp oauth storage" do
    let(:storage) { described_class.new }
    let(:approved_by) { { user_id: 42 } }
  end
end
