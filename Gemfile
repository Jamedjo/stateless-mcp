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

# Only for the OAuth gem's specs. Its default client metadata fetcher loads
# ssrf_filter when it's built, so no gem depends on it.
gem "ssrf_filter", require: false
gem "webmock", require: false
