require "active_record"
require "active_support/key_generator"

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

# Builds each docs recipe from its files into a separate module.
module OAuthRecipes
  DIR = File.join(__dir__, "../recipes")

  # Stands in for Rails.application, with a random secret_key_base.
  Rails = Struct.new(:application).new(Struct.new(:key_generator).new(ActiveSupport::KeyGenerator.new(SecureRandom.hex(64))))

  # Creates a module called name and loads each file step into it. A block
  # step is class_eval'd on the McpOAuthStorage built so far.
  def self.build(name, *steps)
    const_set(name, Module.new).tap do |recipe|
      recipe.const_set(:Rails, Rails)
      steps.each do |step|
        if step.is_a?(Proc)
          recipe.const_get(:McpOAuthStorage).class_eval(&step)
        else
          recipe.module_eval(File.read(File.join(DIR, step)), File.join(DIR, step))
        end
      end
    end
  end

  def self.migrate(*migrations)
    ActiveRecord::Migration.verbose = false
    migrations.each { |migration| migration.migrate(:up) }
  end

  GRANTS = %w[grants/create_mcp_grants.rb grants/mcp_grant.rb grants/mcp_oauth_storage.rb].freeze
  ENCRYPTED = %w[encrypted_tokens/add_refresh_token_id_to_mcp_grants.rb encrypted_tokens/mcp_oauth_storage.rb].freeze
  TOKEN_ROWS = %w[token_rows/create_mcp_tokens.rb token_rows/mcp_token.rb token_rows/mcp_oauth_storage.rb].freeze

  build :Encrypted, *GRANTS, *ENCRYPTED
  build :TokenRows, *GRANTS, *TOKEN_ROWS
  # Switching renames the encrypted-token methods and removes issue_tokens, as
  # the docs instruct. The token-row methods are then loaded over them.
  build :Switching, *GRANTS, *ENCRYPTED, proc {
    alias_method :read_encrypted_token, :read_token
    alias_method :consume_encrypted_refresh_token, :consume_refresh_token
    remove_method :issue_tokens
  }, *TOKEN_ROWS, "switching/mcp_oauth_storage.rb"
end
