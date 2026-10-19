source "https://rubygems.org"

gemspec path: "stateless-mcp"
gemspec path: "stateless-mcp-rails"
gemspec path: "stateless-mcp-oauth"

gem "appraisal", require: false # gemfiles/ for specs against other gems or versions
gem "rack-test"
gem "rake", require: false # `rake release`, from the Rakefile at the root
gem "rspec", "~> 3.13"
gem "rubocop-rails-omakase", require: false

# Only for the ActiveRecord paging and OAuth storage recipe specs. No gem depends on these.
gem "activerecord", require: false
gem "sqlite3", require: false
