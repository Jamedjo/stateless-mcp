require "stateless_mcp/oauth/storage_check"

module StatelessMcp
  module OAuth
    class StorageCheck
      # A Minitest test for each storage check. The test class defines storage
      # and approved_by:
      #
      #   class McpOAuthStorageTest < ActiveSupport::TestCase
      #     include StatelessMcp::OAuth::StorageCheck::Minitest
      #
      #     def storage
      #       McpOAuthStorage.new
      #     end
      #
      #     def approved_by
      #       { user_id: 42 }
      #     end
      #   end
      module Minitest
        def self.included(test_class)
          CHECKS.each_key do |name|
            test_class.define_method("test_storage_#{name}") do
              StorageCheck.new(storage, approved_by: approved_by).run(name)
            rescue Failure => failure
              flunk failure.message
            end
          end
        end
      end
    end
  end
end
