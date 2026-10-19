RSpec.describe StatelessMcp::OAuth::Claims do
  let(:request) { { "client_id" => "https://client.example/metadata.json", "redirect_uri" => "https://client.example/callback", "code_challenge" => "abc", "scope" => "notes:read", "resource" => "https://app.example/mcp" } }
  let(:approved_by) { { "user_id" => 42 } }

  def code(**overrides)
    described_class.new(kind: :code, id: "c1", expires_at: 1_800_000_000, authorization_request: request, approved_by: approved_by, **overrides)
  end

  it "round-trips through to_h and JSON" do
    expect(described_class.from_h(JSON.parse(JSON.generate(code.to_h)))).to eq(code)
  end

  it "converts to a JSON-safe hash" do
    access = described_class.new(kind: :access, id: "a1", grant_id: "g1", expires_at: 100)

    expect(access.to_h).to eq(kind: "access", id: "a1", grant_id: "g1", expires_at: 100)
  end

  it "keeps only the authorization request's known fields, and all of approved_by" do
    claims = code(authorization_request: request.merge("admin" => true), approved_by: { "org_id" => 3, "bot_id" => 7 })

    expect(claims.authorization_request.keys).to eq(described_class::AUTHORIZATION_REQUEST)
    expect(claims.approved_by).to eq(org_id: 3, bot_id: 7)
  end

  it "rejects invalid claims" do
    expect { code(grant_id: "g") }.to raise_error(ArgumentError, /nil for an authorization code/)
    expect { described_class.new(kind: :access, id: "a", expires_at: 1) }.to raise_error(ArgumentError, /grant_id must be a String/)
    expect { code(approved_by: nil) }.to raise_error(ArgumentError, /approved_by is required/)
    expect { code(authorization_request: nil) }.to raise_error(ArgumentError, /authorization_request is required/)
    expect { described_class.new(kind: :session, id: "a", grant_id: "c", expires_at: 1) }.to raise_error(ArgumentError, /kind/)
    expect { described_class.new(kind: :access, id: "a", grant_id: "c", expires_at: "1") }.to raise_error(ArgumentError, /expires_at must be an Integer/)
    expect { described_class.new(kind: :access, id: "a", grant_id: "c", expires_at: 1, approved_by: approved_by) }.to raise_error(ArgumentError, /not allowed for other kinds/)
  end

  it "ignores keys the storage added" do
    expect(described_class.from_h({ "kind" => "access", "id" => "a", "grant_id" => "g", "expires_at" => 1, "refresh_token_id" => "r" })).to eq(described_class.new(kind: :access, id: "a", grant_id: "g", expires_at: 1))
  end

  it "returns nil for a hash that isn't valid claims" do
    expect(described_class.from_h({ "kind" => "access" })).to be_nil
    expect(described_class.from_h("access")).to be_nil
  end

  it "is expired from expires_at onward" do
    claims = described_class.new(kind: :access, id: "a", grant_id: "c", expires_at: 100)

    expect(claims.expired?(Time.at(99))).to be(false)
    expect(claims.expired?(Time.at(100))).to be(true)
  end
end
