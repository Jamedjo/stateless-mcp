require "securerandom"
require "stateless_mcp/oauth"

module StatelessMcp
  module OAuth
    # Checks a StatelessMcp::OAuth::Storage subclass against everything the
    # gem relies on, with no test framework. The Minitest and RSpec adapters
    # in storage_check/ turn each check into a test. They live in
    # test_support/, not lib/, so the gem never loads them itself:
    #
    #   check = StorageCheck.new(McpOAuthStorage.new, approved_by: { user_id: 42 })
    #   check.run(:taken_grant_id) # raises StorageCheck::Failure if it fails
    #   check.run_all
    #
    # approved_by is the attributes the app's grants keep for who approved,
    # with values its storage can store.
    #
    # The race checks use threads, so every database connection must reach
    # the same database. A SQLite file works. An in-memory SQLite database
    # doesn't.
    class StorageCheck
      Failure = Class.new(StandardError)

      CHECKS = {
        full_sign_in: "takes a sign-in from authorization code to refreshed tokens, and rejects a reused refresh token",
        create_and_find_grant: "creates a grant, returning its id, and finds it with its approved_by attributes",
        distinct_grants: "gives each authorization code's grant a different id",
        unknown_grant: "finds no grant for an unknown id",
        used_code: "returns nil for an authorization code already exchanged, leaving every field of its grant unchanged",
        revoked_grant: "stops finding a revoked grant, and still returns nil for its authorization code",
        create_grant_race: "creates one grant when requests race to exchange the same authorization code",
        token_round_trip: "reads back the claims of each kind of token",
        token_characters: "issues tokens safe to send in a header or form without encoding",
        unknown_tokens: "returns nil for tokens it didn't issue",
        revoked_token: "stops a revoked token working, by revoking the token or its grant",
        issued_pair: "issues an access token and a refresh token together, each reading back",
        consume_once: "consumes a refresh token once, returning true then false",
        used_refresh_token_reads: "still reads a used refresh token, so its reuse can be caught",
        consume_race: "consumes a refresh token once when requests race to use it"
      }.freeze

      RACERS = 8

      def initialize(storage, approved_by:)
        raise ArgumentError, "approved_by must be a Hash, such as { user_id: 42 }" unless approved_by.is_a?(Hash)
        @storage = storage
        @approved_by = approved_by
      end

      def checks
        CHECKS.keys
      end

      def run(name)
        raise ArgumentError, "no storage check called #{name.inspect}" unless CHECKS.key?(name)
        public_send(name)
      end

      def run_all
        checks.each { |name| run(name) }
      end

      def full_sign_in
        code = read_claims(@storage.issue_token(claims(:code)))
        check(code&.dig(:kind) == "code", "read_token didn't return the authorization code's claims")
        grant_id = @storage.create_grant(**grant_arguments(code[:id]))
        check(grant_id.is_a?(String), "create_grant returned #{grant_id.inspect} for a new authorization code, not the grant's id")

        _access, refresh = issue_pair(grant_id)
        check_approved_by(@storage.find_grant(grant_id))

        check(@storage.consume_refresh_token(refresh) == true, "consume_refresh_token didn't return true for a new refresh token")
        _access, next_refresh = issue_pair(grant_id)
        check(@storage.consume_refresh_token(refresh) == false, "consume_refresh_token didn't return false for a used refresh token")
        check(@storage.consume_refresh_token(next_refresh) == true, "consume_refresh_token didn't return true for the next refresh token")
      end

      def create_and_find_grant
        arguments = grant_arguments
        id = @storage.create_grant(**arguments)
        check(id.is_a?(String), "create_grant returned #{id.inspect} for a new authorization code, not the grant's id")
        grant = @storage.find_grant(id)
        check(grant, "find_grant returned nil for a grant just created")
        check(grant.id == id, "find_grant's id was #{grant.id.inspect}, not #{id.inspect} as create_grant returned")
        %i[client_id resource scope].each do |name|
          expected = arguments[:authorization_request][name]
          check(grant.public_send(name) == expected, "find_grant's #{name} was #{grant.public_send(name).inspect}, not #{expected.inspect}")
        end
        check_approved_by(grant)
      end

      def distinct_grants
        ids = 2.times.map { @storage.create_grant(**grant_arguments) }
        check(ids.uniq.size == 2, "create_grant returned the same grant id, #{ids.first.inspect}, for two authorization codes")
      end

      def unknown_grant
        check(@storage.find_grant(SecureRandom.uuid).nil?, "find_grant didn't return nil for an unknown id")
      end

      def used_code
        arguments = grant_arguments
        id = @storage.create_grant(**arguments)
        changed = { client_id: "https://other.example/metadata.json", resource: "https://other.example/mcp", scope: "notes:write" }
        again = @storage.create_grant(**arguments, authorization_request: changed)
        check(again.nil?, "create_grant returned #{again.inspect} for an authorization code already exchanged, not nil")
        grant = @storage.find_grant(id)
        arguments[:authorization_request].each do |name, value|
          check(grant&.public_send(name) == value, "create_grant changed the #{name} of a grant whose authorization code was already exchanged")
        end
      end

      def revoked_grant
        arguments = grant_arguments
        id = @storage.create_grant(**arguments)
        @storage.revoke_grant(id)
        check(@storage.find_grant(id).nil?, "find_grant still found a revoked grant")
        check(@storage.create_grant(**arguments).nil?, "create_grant made a new grant for a revoked grant's authorization code")
      end

      def create_grant_race
        arguments = grant_arguments
        created = in_threads { @storage.create_grant(**arguments) }.compact.size
        check(created == 1, "#{created} of #{RACERS} racing create_grant calls returned a grant id, not 1")
      end

      def token_round_trip
        grant_id = new_grant
        [claims(:code), claims(:access, grant_id), claims(:refresh, grant_id)].each do |issued|
          read = Claims.from_h(read_claims(@storage.issue_token(issued)))
          check(read == Claims.from_h(issued), "read_token returned #{read.inspect} for a #{issued[:kind]} token issued with #{issued.inspect}")
        end
      end

      def token_characters
        token = @storage.issue_token(claims(:access, new_grant))
        check(token.is_a?(String) && token.match?(%r{\A[A-Za-z0-9\-._~+/]+=*\z}), "issue_token returned #{token.inspect}, which isn't safe to send unencoded")
      end

      def unknown_tokens
        ["", "nonsense", "a" * 5000, "a--b--c"].each do |token|
          check(@storage.read_token(token).nil?, "read_token didn't return nil for #{token[0, 20].inspect}")
        end
      end

      def revoked_token
        grant_id = new_grant
        token = @storage.issue_token(claims(:access, grant_id))
        @storage.revoke_token(read_claims(token))
        check(@storage.read_token(token).nil? || @storage.find_grant(grant_id).nil?, "a revoked token still read, and its grant was still found")
      end

      def issued_pair
        grant_id = new_grant
        access, refresh = @storage.issue_tokens(claims(:access, grant_id), claims(:refresh, grant_id))
        check(Claims.from_h(read_claims(access))&.kind == :access, "issue_tokens' first token didn't read back as the access token")
        check(Claims.from_h(read_claims(refresh))&.kind == :refresh, "issue_tokens' second token didn't read back as the refresh token")
      end

      def consume_once
        _access, refresh = issue_pair(new_grant)
        check(@storage.consume_refresh_token(refresh) == true, "consume_refresh_token didn't return true the first time")
        check(@storage.consume_refresh_token(refresh) == false, "consume_refresh_token didn't return false the second time")
      end

      def used_refresh_token_reads
        token = @storage.issue_tokens(claims(:access, grant_id = new_grant), claims(:refresh, grant_id)).last
        @storage.consume_refresh_token(read_claims(token))
        check(Claims.from_h(read_claims(token))&.kind == :refresh, "read_token returned nil for a used refresh token, so the gem can't tell when it's used again")
      end

      def consume_race
        _access, refresh = issue_pair(new_grant)
        consumed = in_threads { @storage.consume_refresh_token(refresh) }.count(true)
        check(consumed == 1, "#{consumed} of #{RACERS} racing consume_refresh_token calls returned true, not 1")
      end

      private
        def check(condition, message)
          raise Failure, message unless condition
        end

        def check_approved_by(grant)
          @approved_by.each do |name, value|
            actual = grant.public_send(name)
            check(actual == value, "find_grant's #{name} was #{actual.inspect}, not #{value.inspect} as passed to create_grant")
          end
        end

        def grant_arguments(code_id = SecureRandom.uuid)
          { code_id: code_id, authorization_request: { client_id: "https://client.example/metadata.json", resource: "https://app.example/mcp", scope: "notes:read" }, approved_by: @approved_by }
        end

        def new_grant
          @storage.create_grant(**grant_arguments)
        end

        def claims(kind, grant_id = nil, expires_at: Time.now.to_i + 3600)
          request = { client_id: "https://client.example/metadata.json", redirect_uri: "https://client.example/callback", code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", scope: "notes:read", resource: "https://app.example/mcp" } if kind == :code
          Claims.new(kind: kind, id: SecureRandom.uuid, grant_id: grant_id, expires_at: expires_at, authorization_request: request, approved_by: (@approved_by if kind == :code)).to_h
        end

        # Issues an access token and a refresh token as the gem does, and
        # returns their claims as the gem reads them.
        def issue_pair(grant_id)
          @storage.issue_tokens(claims(:access, grant_id), claims(:refresh, grant_id)).map { |token| read_claims(token) }
        end

        # A token's claims as the gem reads them. Keys are symbols, and keys
        # the storage added are kept.
        def read_claims(token)
          Claims.symbolize(@storage.read_token(token))
        end

        def in_threads(&block)
          RACERS.times.map { Thread.new(&block) }.map(&:value)
        end
    end
  end
end
