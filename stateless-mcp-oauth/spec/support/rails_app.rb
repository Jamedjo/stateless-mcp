require "stateless_mcp/rails"

# A Rails app that is never booted, so the examples can set
# Rails.application.config.stateless_mcp as an app's initializer does.
class OAuthExamplesApp < Rails::Application
  config.eager_load = false
  config.logger = Logger.new(nil)
  config.secret_key_base = "examples"
end
