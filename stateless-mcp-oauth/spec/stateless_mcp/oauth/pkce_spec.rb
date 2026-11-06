RSpec.describe StatelessMcp::OAuth::Pkce do
  # RFC 7636, appendix B.
  let(:verifier) { "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk" }
  let(:challenge) { "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM" }

  it "derives the S256 challenge" do
    expect(described_class.challenge_for(verifier)).to eq(challenge)
  end

  it "verifies only the verifier the challenge came from" do
    expect(described_class.verified?(verifier, challenge)).to be(true)
    expect(described_class.verified?(verifier.reverse, challenge)).to be(false)
    expect(described_class.verified?(verifier, verifier)).to be(false)
  end

  it "refuses verifiers outside RFC 7636's length and characters" do
    short = "a" * 42
    expect(described_class.verified?(short, described_class.challenge_for(short))).to be(false)
    spaced = "a b" * 20
    expect(described_class.verified?(spaced, described_class.challenge_for(spaced))).to be(false)
    expect(described_class.verified?(nil, challenge)).to be(false)
  end

  it "compares in constant time" do
    allow(Rack::Utils).to receive(:secure_compare).and_call_original

    described_class.verified?(verifier, challenge)

    expect(Rack::Utils).to have_received(:secure_compare).with(challenge, challenge)
  end
end
