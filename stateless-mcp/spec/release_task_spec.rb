require "stringio"
require_relative "../../tasks/release"

# The repository's `rake release`, against a shell that runs nothing.
RSpec.describe Release do
  let(:shell) { FakeShell.new }
  let(:out) { StringIO.new }
  let(:release) { described_class.new(root: "/repo", version: "1.2.3", shell: shell, out: out) }

  class FakeShell
    attr_reader :runs
    attr_accessor :status, :head, :local_tag, :github_tag, :ykman, :failing

    def initialize
      @runs = []
      @status = ""
      @head = "abc123"
      @local_tag = false
      @github_tag = ""
      @ykman = true
    end

    def run(*command, env: {}, chdir: ".")
      raise Release::Error, "Failed: #{command.join(" ")}" if command == failing
      runs << [chdir == "." ? command : [ "cd", chdir, "&&", *command ], env]
    end

    def capture(*command)
      case command
      in ["git", "status", *] then status
      in ["git", "rev-parse", "HEAD"] then head
      in ["git", "rev-parse", "gitlab/main"] then "abc123"
      in ["git", "ls-remote", *] then github_tag
      in ["ykman", *] then "424242"
      end
    end

    def success?(*)
      local_tag
    end

    def installed?(program)
      program == "ykman" && ykman
    end

    def commands
      runs.map(&:first)
    end
  end

  it "fetches, builds the core gem then the Rails gem, pushes the tag, then pushes each gem with a fresh code" do
    release.run

    expect(shell.commands).to eq([
      %w[git fetch gitlab --tags],
      %w[mkdir -p /repo/pkg],
      %w[cd stateless-mcp && gem build stateless-mcp.gemspec --output /repo/pkg/stateless-mcp-1.2.3.gem],
      %w[cd stateless-mcp-rails && gem build stateless-mcp-rails.gemspec --output /repo/pkg/stateless-mcp-rails-1.2.3.gem],
      [ "git", "tag", "--annotate", "v1.2.3", "--message", "Version 1.2.3" ],
      %w[git push gitlab v1.2.3],
      %w[git push github v1.2.3],
      %w[gem push /repo/pkg/stateless-mcp-1.2.3.gem],
      %w[gem push /repo/pkg/stateless-mcp-rails-1.2.3.gem]
    ])
    expect(shell.runs.last(2).map(&:last)).to all(eq("GEM_HOST_OTP_CODE" => "424242"))
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

  it "refuses a working tree with changes" do
    shell.status = " M README.md"

    expect { release.run }.to raise_error(Release::Error, /working tree has changes/)
    expect(shell.commands).to eq([%w[git fetch gitlab --tags]])
  end

  it "refuses a HEAD that isn't gitlab/main" do
    shell.head = "def456"

    expect { release.run }.to raise_error(Release::Error, /HEAD is def456, not gitlab\/main/)
  end

  it "refuses a version already tagged here or on GitHub" do
    shell.local_tag = true
    expect { release.run }.to raise_error(Release::Error, "Tag v1.2.3 already exists. Bump StatelessMcp::VERSION for a new release.")

    shell.local_tag = false
    shell.github_tag = "abc123\trefs/tags/v1.2.3"
    expect { release.run }.to raise_error(Release::Error, /Tag v1.2.3 already exists/)
    expect(shell.commands).to all(start_with("git"))
  end

  it "says which gems are left when a push fails" do
    shell.failing = %w[gem push /repo/pkg/stateless-mcp-1.2.3.gem]

    expect { release.run }.to raise_error(Release::Error, /stateless-mcp isn't on RubyGems.org.*gem push \/repo\/pkg\/stateless-mcp-1.2.3.gem && gem push \/repo\/pkg\/stateless-mcp-rails-1.2.3.gem/)
  end

  it "tags the version the core gem declares" do
    expect(described_class.new(root: "/repo", shell: shell, out: out).tag).to eq("v#{StatelessMcp::VERSION}")
  end
end
