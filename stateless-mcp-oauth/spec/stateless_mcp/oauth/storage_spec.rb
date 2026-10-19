RSpec.describe StatelessMcp::OAuth::Storage do
  let(:storage) { Class.new(described_class) { define_singleton_method(:name) { "AppStorage" } }.new }
  let(:access) { { kind: "access", id: "t1", grant_id: "g1", expires_at: 1 } }

  it "names each required method the app hasn't defined" do
    expect { storage.create_grant(code_id: "c1", authorization_request: { client_id: "c", resource: "r", scope: "s" }, approved_by: { user_id: 1 }) }.to raise_error(NotImplementedError, "AppStorage must define create_grant")
    expect { storage.find_grant("g1") }.to raise_error(NotImplementedError, /find_grant/)
    expect { storage.revoke_grant("g1") }.to raise_error(NotImplementedError, /revoke_grant/)
    expect { storage.issue_token(access) }.to raise_error(NotImplementedError, /issue_token/)
    expect { storage.read_token("token") }.to raise_error(NotImplementedError, /read_token/)
    expect { storage.consume_refresh_token(access) }.to raise_error(NotImplementedError, /consume_refresh_token/)
  end

  it "revokes the token's grant by default" do
    allow(storage).to receive(:revoke_grant)

    storage.revoke_token(access)

    expect(storage).to have_received(:revoke_grant).with("g1")
  end
end
