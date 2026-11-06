require "securerandom"

# In-memory storage, for specs of the code that calls storage. It passes
# StorageCheck, like an app's storage class.
class MemoryStorage < StatelessMcp::OAuth::Storage
  Grant = Struct.new(:id, :client_id, :resource, :scope, :user_id, :revoked, keyword_init: true)

  def initialize
    @lock = Mutex.new
    @grants = {}
    @tokens = {}
    @consumed = {}
  end

  def create_grant(code_id:, authorization_request:, approved_by:)
    @lock.synchronize do
      next nil if @grants.key?(code_id)
      @grants[code_id] = Grant.new(id: code_id, **authorization_request, user_id: approved_by[:user_id], revoked: false)
      code_id
    end
  end

  def find_grant(id)
    @lock.synchronize { @grants[id] unless @grants[id]&.revoked }
  end

  def revoke_grant(id)
    @lock.synchronize { @grants[id]&.revoked = true }
  end

  def issue_token(claims)
    SecureRandom.urlsafe_base64(32).tap { |token| @lock.synchronize { @tokens[token] = claims } }
  end

  def read_token(token)
    @lock.synchronize { @tokens[token] }
  end

  def consume_refresh_token(claims)
    @lock.synchronize { @consumed[claims[:id]] ? false : (@consumed[claims[:id]] = true) }
  end

  def revoke_token(claims)
    @lock.synchronize { @tokens.delete_if { |_token, stored| stored[:id] == claims[:id] } }
  end
end
