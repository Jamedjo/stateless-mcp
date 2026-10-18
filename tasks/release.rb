require "open3"
require_relative "../stateless-mcp/lib/stateless_mcp/version"

# Releases both gems from a checkout of gitlab/main, in the order bundler's
# `rake release` uses: check, build, tag and push the tag, then push the gems.
# See RELEASING.md.
class Release
  Error = Class.new(StandardError)

  # The core gem first, since the Rails gem depends on it at the same version.
  GEMS = %w[stateless-mcp stateless-mcp-rails].freeze

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
  end

  def initialize(root:, version: StatelessMcp::VERSION, shell: Shell.new, out: $stdout)
    @root = root
    @version = version
    @shell = shell
    @out = out
  end

  def tag
    "v#{@version}"
  end

  def run
    check_checkout
    check_tag
    build_gems
    push_tag
    push_gems
    step "Released #{tag}"
  end

  def check_checkout
    step "Fetching gitlab"
    sh "git", "fetch", "gitlab", "--tags"

    step "Checking the checkout"
    unless @shell.capture("git", "status", "--porcelain").empty?
      raise Error, "The working tree has changes. Commit or stash them, then release from gitlab/main."
    end
    head = @shell.capture("git", "rev-parse", "HEAD")
    main = @shell.capture("git", "rev-parse", "gitlab/main")
    unless head == main
      raise Error, "HEAD is #{head[0, 8]}, not gitlab/main (#{main[0, 8]}). Release only what was merged: git checkout --detach gitlab/main"
    end
  end

  def check_tag
    step "Checking #{tag} is new"
    if @shell.success?("git", "rev-parse", "--quiet", "--verify", "refs/tags/#{tag}") ||
        !@shell.capture("git", "ls-remote", "--tags", "github", "refs/tags/#{tag}").empty?
      raise Error, "Tag #{tag} already exists. Bump StatelessMcp::VERSION for a new release."
    end
  end

  def build_gems
    sh "mkdir", "-p", File.join(@root, "pkg")
    GEMS.each do |name|
      step "Building #{name} #{@version}"
      sh "gem", "build", "#{name}.gemspec", "--output", package(name), chdir: name
    end
  end

  def push_tag
    step "Tagging #{tag}"
    sh "git", "tag", "--annotate", tag, "--message", "Version #{@version}"
    %w[gitlab github].each do |remote|
      step "Pushing #{tag} to #{remote}"
      sh "git", "push", remote, tag
    end
  end

  def push_gems
    GEMS.each_with_index do |name, index|
      step "Pushing #{name} #{@version} to RubyGems.org"
      sh "gem", "push", package(name), env: one_time_code
    rescue Error
      rest = GEMS.drop(index).map { |gem| "gem push #{package(gem)}" }
      raise Error, "#{tag} is tagged and pushed, but #{name} isn't on RubyGems.org. Push the rest by hand: #{rest.join(" && ")}"
    end
  end

  private
    def package(name)
      File.join(@root, "pkg", "#{name}-#{@version}.gem")
    end

    # A fresh code for each push, since each lasts 30 seconds. Without ykman,
    # gem push asks for one itself.
    def one_time_code
      return {} unless @shell.installed?("ykman")
      step "Reading a one-time code from the YubiKey"
      { "GEM_HOST_OTP_CODE" => @shell.capture("ykman", "oath", "accounts", "code", "-s", "rubygems.org") }
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
