require_relative "tasks/release"

desc "Build both gems from the commit checked out, tag it and push the tag, then push the gems to RubyGems.org"
task :release do
  Release.new(root: __dir__).run
rescue Release::Error => e
  abort "release: #{e.message}"
end
