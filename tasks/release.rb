require "open3"
require "tmpdir"

# Releases both gems from the commit checked out, in the order bundler's
# `rake release` uses: check, build, tag and push the tag, then push the gems.
# Gems are built from an export of that commit, so nothing uncommitted or
# ignored in the working tree can reach them. A release that stopped part way
# picks up where it left off when run again. See RELEASING.md.
class Release
  Error = Class.new(StandardError)

  # The core gem first, since the Rails gem depends on it at the same version.
  GEMS = %w[stateless-mcp stateless-mcp-rails].freeze
  VERSION_FILE = "stateless-mcp/lib/stateless_mcp/version.rb".freeze

  # Runs commands for real. The specs swap in a fake.
  class Shell
    def run(*command, env: {}, chdir: ".")
      system(env, *command, chdir: chdir) or raise Error, "Failed: #{command.join(" ")}"
    end

    def capture(*command)
      output, status = Open3.capture2(*command)
      raise Error, "Failed: #{command.join(" ")}" unless status.success?
      output.strip
    end

    def success?(*command)
      system(*command, out: File::NULL, err: File::NULL)
    end

    def installed?(program)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, program)) }
    end

    def tmpdir(&)
      Dir.mktmpdir("stateless-mcp-release", &)
    end
  end

  def initialize(root:, shell: Shell.new, out: $stdout)
    @root = root
    @shell = shell
    @out = out
  end

  def run
    check_commit
    check_tag
    @shell.tmpdir do |dir|
      export(dir)
      build_gems(dir)
    end
    push_tag
    push_gems
    step "Released #{tag}"
  end

  private
    def commit
      @commit ||= @shell.capture("git", "rev-parse", "HEAD")
    end

    def version
      @version ||= @shell.capture("git", "show", "#{commit}:#{VERSION_FILE}")[/VERSION = "([^"]+)"/, 1] or
        raise Error, "No VERSION in #{VERSION_FILE} at #{short(commit)}."
    end

    def tag
      "v#{version}"
    end

    def check_commit
      step "Fetching gitlab"
      sh "git", "fetch", "gitlab", "--tags"

      # An embargoed fix may be released straight from a local branch, so this only warns.
      unless @shell.capture("git", "branch", "--remotes", "--contains", commit).split.any? { |ref| ref.start_with?("gitlab/") }
        step "Warning: #{short(commit)} isn't on any GitLab branch, so it hasn't been reviewed there. The tag push publishes it"
      end
      unless @shell.capture("git", "status", "--porcelain").empty?
        step "Ignoring uncommitted changes: building #{short(commit)} as committed"
      end
    end

    # A tag on this commit means an earlier run got that far, so it's reused.
    def check_tag
      step "Checking #{tag}"
      return unless @shell.success?("git", "rev-parse", "--quiet", "--verify", "refs/tags/#{tag}")
      unless @shell.capture("git", "rev-parse", "#{tag}^{commit}") == commit
        raise Error, "#{tag} already tags another commit. Bump StatelessMcp::VERSION for a new release."
      end
      @tagged = true
    end

    def export(dir)
      step "Exporting #{short(commit)}"
      sh "git", "archive", "--output", File.join(dir, "source.tar"), commit
      sh "tar", "--extract", "--file", "source.tar", chdir: dir
    end

    # Dated by the commit, so building the same commit twice gives the same gems.
    def build_gems(dir)
      sh "mkdir", "-p", File.join(@root, "pkg")
      epoch = @shell.capture("git", "show", "--no-patch", "--format=%ct", commit)
      GEMS.each do |name|
        step "Building #{name} #{version}"
        sh "gem", "build", "#{name}.gemspec", "--output", package(name), env: { "SOURCE_DATE_EPOCH" => epoch }, chdir: File.join(dir, name)
      end
    end

    # Pushing a tag a remote already has at the same commit succeeds quietly.
    def push_tag
      unless @tagged
        step "Tagging #{short(commit)} as #{tag}"
        sh "git", "tag", "--annotate", tag, "--message", "Version #{version}", commit
      end
      %w[gitlab github].each do |remote|
        step "Pushing #{tag} to #{remote}"
        sh "git", "push", remote, tag
      end
    end

    def push_gems
      GEMS.each do |name|
        if published?(name)
          step "#{name} #{version} is already on RubyGems.org"
          next
        end
        step "Pushing #{name} #{version} to RubyGems.org"
        sh "gem", "push", package(name), env: one_time_code
      end
    rescue Error => e
      raise Error, "#{e.message}. #{tag} is tagged, but not every gem is on RubyGems.org. Run rake release again to push the rest."
    end

    def published?(name)
      @shell.success?("curl", "--silent", "--fail", "--output", File::NULL, "https://rubygems.org/api/v2/rubygems/#{name}/versions/#{version}.json")
    end

    def package(name)
      File.join(@root, "pkg", "#{name}-#{version}.gem")
    end

    # A fresh code for each push, since each lasts 30 seconds. Without ykman,
    # gem push asks for one itself.
    def one_time_code
      return {} unless @shell.installed?("ykman")
      step "Touch the YubiKey for a one-time code"
      { "GEM_HOST_OTP_CODE" => @shell.capture("ykman", "oath", "accounts", "code", "-s", "rubygems.org") }
    end

    def short(sha)
      sha[0, 8]
    end

    # Prints the command, never its environment, so the code stays hidden.
    def sh(*command, env: {}, chdir: ".")
      @out.puts "   $ #{"cd #{chdir} && " unless chdir == "."}#{command.join(" ")}"
      @shell.run(*command, env: env, chdir: chdir)
    end

    def step(message)
      @out.puts "==> #{message}"
    end
end
