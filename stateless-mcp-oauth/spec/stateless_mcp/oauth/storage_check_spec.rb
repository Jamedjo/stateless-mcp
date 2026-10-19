RSpec.describe StatelessMcp::OAuth::StorageCheck do
  # Every method claims success, as a careless storage class might.
  let(:careless) do
    Class.new(StatelessMcp::OAuth::Storage) do
      def create_grant(**)
        "g1"
      end

      def find_grant(_id)
        nil
      end
    end.new
  end

  it "names the rule a storage class broke" do
    check = described_class.new(careless, approved_by: { user_id: 42 })

    expect { check.run(:used_code) }.to raise_error(described_class::Failure, 'create_grant returned "g1" for an authorization code already exchanged, not nil')
    expect { check.run(:unknown_grant) }.not_to raise_error
  end

  it "lists every check, and refuses one it doesn't have" do
    check = described_class.new(careless, approved_by: { user_id: 42 })

    expect(check.checks).to eq(described_class::CHECKS.keys)
    expect { check.run(:no_such_check) }.to raise_error(ArgumentError, /no storage check called :no_such_check/)
  end

  it "needs approved_by as a hash" do
    expect { described_class.new(careless, approved_by: 42) }.to raise_error(ArgumentError, /approved_by must be a Hash/)
  end
end
