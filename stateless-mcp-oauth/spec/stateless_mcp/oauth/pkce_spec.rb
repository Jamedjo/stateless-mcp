RSpec.describe StatelessMcp::OAuth::Pkce do
  # RFC 7636, appendix B.
  let(:verifier) { "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk" }
  let(:challenge) { "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM" }

  # Whether a verifier would pass with the challenge derived from it, so only
  # its format decides.
  def verifies_itself?(candidate)
    described_class.verified?(candidate, described_class.challenge_for(candidate))
  end

  it "derives the S256 challenge" do
    expect(described_class.challenge_for(verifier)).to eq(challenge)
  end

  it "verifies only the verifier the challenge came from" do
    expect(described_class.verified?(verifier, challenge)).to be(true)
    expect(described_class.verified?(verifier.reverse, challenge)).to be(false)
    expect(described_class.verified?(verifier, verifier)).to be(false)
  end

  it "refuses a challenge one character away from the right one" do
    expect(described_class.verified?(verifier, "#{challenge.chop}d")).to be(false)
  end

  it "accepts verifiers of 43 to 128 unreserved characters" do
    expect(verifies_itself?("a" * 43)).to be(true)
    expect(verifies_itself?("a" * 128)).to be(true)
    expect(verifies_itself?("A-z.0_9~" * 6)).to be(true)
  end

  it "refuses verifiers outside RFC 7636's length and characters" do
    ["a" * 42, "a" * 129, "a b" * 20, "#{"a" * 43}\n", "é" * 43].each do |candidate|
      expect(verifies_itself?(candidate)).to be(false), candidate.inspect
    end
    expect(described_class.verified?(nil, challenge)).to be(false)
  end

  it "refuses badly encoded input rather than raising" do
    invalid = "#{"a" * 43}\xFF".dup.force_encoding("UTF-8")
    wide = ("a" * 43).encode("UTF-16LE")

    expect(described_class.verified?(invalid, challenge)).to be(false)
    expect(described_class.verified?(wide, challenge)).to be(false)
    expect(described_class.verified?(verifier, challenge.encode("UTF-32BE"))).to be(false)
    expect(described_class.challenge?("#{challenge}\xFF".dup.force_encoding("UTF-8"))).to be(false)
  end

  describe ".challenge?" do
    it "accepts an unpadded base64url SHA-256 digest" do
      expect(described_class.challenge?(challenge)).to be(true)
    end

    it "refuses padding, standard base64, the wrong length, a trailing newline and nil" do
      ["#{challenge}=", challenge.tr("-", "+"), "#{challenge.chop}/", challenge.chop, "#{challenge}A", "#{challenge}\n", nil].each do |candidate|
        expect(described_class.challenge?(candidate)).to be(false), candidate.inspect
      end
    end
  end
end
