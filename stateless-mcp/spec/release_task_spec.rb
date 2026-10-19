require "stringio"
require_relative "../../tasks/release"

# The repository's `rake release`, against a shell that runs nothing.
RSpec.describe Release do
  let(:shell) { FakeShell.new }
  let(:out) { StringIO.new }
  let(:release) { described_class.new(root: "/repo", shell: shell, out: out) }

  class FakeShell
    attr_reader :runs
    attr_accessor :status, :branches, :tagged, :published, :ykman, :failing

    def initialize
      @runs = []
      @status = ""
      @branches = "  gitlab/main\n  github/main"
      @tagged = nil
      @published = []
      @ykman = true
    end

    def run(*command, env: {}, chdir: ".")
      raise Release::Error, "Failed: #{command.join(" ")}" if command == failing
      runs << [chdir == "." ? command : [ "cd", chdir, "&&", *command ], env]
    end

    def capture(*command)
      case command
      in ["git", "rev-parse", "HEAD"] then "abc123def456"
      in ["git", "rev-parse", /\^\{commit\}\z/] then tagged
      in ["git", "show", "abc123def456:stateless-mcp/lib/stateless_mcp/version.rb"] then %(module StatelessMcp\n  VERSION = "1.2.3"\nend)
      in ["git", "show", "--no-patch", *] then "1760000000"
      in ["git", "branch", *] then branches
      in ["git", "status", *] then status
      in ["ykman", *] then "424242"
      end
    end

    def success?(*command)
      case command
      in ["git", "rev-parse", *] then !tagged.nil?
      in ["curl", *, url] then published.any? { |name| url.include?("/rubygems/#{name}/versions/1.2.3.json") }
      end
    end

    def installed?(program)
      program == "ykman" && ykman
    end

    def tmpdir
      yield "/tmp/build"
    end

    def commands
      runs.map(&:first)
    end
  end

  it "builds both gems from an export of HEAD, tags HEAD and pushes the tag, then pushes each gem with a fresh code" do
    release.run

    expect(shell.commands).to eq([
      %w[git fetch gitlab --tags],
      %w[git archive --output /tmp/build/source.tar abc123def456],
      %w[cd /tmp/build && tar --extract --file source.tar],
      %w[mkdir -p /repo/pkg],
      %w[cd /tmp/build/stateless-mcp && gem build stateless-mcp.gemspec --output /repo/pkg/stateless-mcp-1.2.3.gem],
      %w[cd /tmp/build/stateless-mcp-rails && gem build stateless-mcp-rails.gemspec --output /repo/pkg/stateless-mcp-rails-1.2.3.gem],
      [ "git", "tag", "--annotate", "v1.2.3", "--message", "Version 1.2.3", "abc123def456" ],
      %w[git push gitlab v1.2.3],
      %w[git push github v1.2.3],
      %w[gem push /repo/pkg/stateless-mcp-1.2.3.gem],
      %w[gem push /repo/pkg/stateless-mcp-rails-1.2.3.gem]
    ])
    expect(shell.runs.last(2).map(&:last)).to all(eq("GEM_HOST_OTP_CODE" => "424242"))
  end

  it "dates the gems by the commit, so the same commit builds the same gems" do
    release.run

    builds = shell.runs.select { |command, _| command.include?("build") }
    expect(builds.map(&:last)).to all(eq("SOURCE_DATE_EPOCH" => "1760000000"))
  end

  it "never prints the one-time code" do
    release.run

    expect(out.string).to include("==> Pushing stateless-mcp-rails 1.2.3 to RubyGems.org")
    expect(out.string).not_to include("424242")
  end

  it "leaves the code to gem push when ykman isn't installed" do
    shell.ykman = false
    release.run

    expect(shell.runs.last(2).map(&:last)).to all(eq({}))
  end

  it "builds what was committed, whatever the working tree holds" do
    shell.status = " M README.md\n?? scratch.rb"
    release.run

    expect(out.string).to include("Ignoring uncommitted changes: building abc123de as committed")
    expect(shell.commands).to include(%w[git archive --output /tmp/build/source.tar abc123def456])
  end

  it "releases from any branch on GitLab, such as a fix for an older version" do
    shell.branches = "  gitlab/security-0.0.2"

    expect { release.run }.not_to raise_error
  end

  it "warns about a commit that isn't on GitLab, then releases it" do
    shell.branches = "  github/main"
    release.run

    expect(out.string).to include("Warning: abc123de isn't on any GitLab branch")
    expect(shell.commands).to include(%w[git push github v1.2.3])
  end

  it "refuses a version tagged on another commit" do
    shell.tagged = "fed987"

    expect { release.run }.to raise_error(Release::Error, "v1.2.3 already tags another commit. Bump StatelessMcp::VERSION for a new release.")
    expect(shell.commands).to eq([%w[git fetch gitlab --tags]])
  end

  it "picks up a stopped release: keeps the tag and pushes only the gems missing from RubyGems.org" do
    shell.tagged = "abc123def456"
    shell.published = ["stateless-mcp"]
    release.run

    expect(shell.commands).not_to include(include("tag"))
    expect(shell.commands.last(3)).to eq([
      %w[git push gitlab v1.2.3],
      %w[git push github v1.2.3],
      %w[gem push /repo/pkg/stateless-mcp-rails-1.2.3.gem]
    ])
    expect(out.string).to include("stateless-mcp 1.2.3 is already on RubyGems.org")
  end

  it "says to run it again when a push fails" do
    shell.failing = %w[gem push /repo/pkg/stateless-mcp-1.2.3.gem]

    expect { release.run }.to raise_error(Release::Error, /v1.2.3 is tagged, but not every gem is on RubyGems.org. Run rake release again/)
  end
end
