# Extra gemfiles for running the specs against other versions of a
# dependency, or with gems the main suites don't load.
# `bundle exec appraisal install` writes them to gemfiles/.

# The oldest and newest Rails versions stateless-mcp-rails supports, and
# those between. The main Gemfile has the latest.
%w[7.2 8.0].each do |version|
  appraise "rails-#{version.tr(".", "-")}" do
    gem "actionpack", "~> #{version}.0"
    gem "railties", "~> #{version}.0"
    gem "activerecord", "~> #{version}.0", require: false
    # json 3 drops an option Active Support passes before 8.1.
    gem "json", "< 3"
  end
end

# For the Doorkeeper recipe spec in docs/oauth-storage-moving.md, which needs
# the doorkeeper gem.
appraise "doorkeeper" do
  gem "doorkeeper", "~> 5.8"
end
