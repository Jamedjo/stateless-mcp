module StatelessMcp
  module OAuth
    # The default cache for client metadata documents: in this process only,
    # holding a bounded number of entries. Any object that responds to
    # read(key) and write(key, value, expires_in:), such as Rails.cache, can
    # replace it.
    class MemoryCache
      def initialize(max_entries: 1000)
        @max_entries = max_entries
        @entries = {}
        @lock = Mutex.new
      end

      def read(key)
        @lock.synchronize do
          value, expires_at = @entries[key]
          next value if expires_at && expires_at > now
          @entries.delete(key)
          nil
        end
      end

      def write(key, value, expires_in:)
        @lock.synchronize do
          @entries.delete(key)
          @entries.shift while @entries.size >= @max_entries
          @entries[key] = [value, now + expires_in]
        end
      end

      private

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
