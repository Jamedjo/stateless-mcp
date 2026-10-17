module StatelessMcp
  # Paging tool results by cursor. A tool declares `paginated` among its
  # arguments, which adds limit and cursor, and pages with these. A list or
  # text is paged by position, so it suits data that doesn't change between
  # calls; records that do are better paged by key, as the Rails ActiveRecord
  # add-on does.
  module Pagination
    # The page size a call asked for, held to the server's limits.
    def self.limit(requested, server)
      (requested.nil? || requested.to_s.empty? ? server.page_size : Integer(requested)).clamp(1, server.max_page_size)
    rescue ArgumentError, TypeError
      server.page_size
    end

    # One page of items, and the cursor for the next while more remain.
    def self.list(items, cursor:, limit:)
      start = offset(cursor)
      rows = items[start, limit + 1] || []
      [rows.first(limit), (Cursor.encode(start + limit) if rows.size > limit)]
    end

    # A long text in parts of part_size characters, and the cursor for the
    # next part while more remains. The block reads length characters of the
    # text from start, so a text kept elsewhere is never read whole.
    def self.text(cursor, part_size)
      start = offset(cursor)
      slice = yield(start, part_size + 1).to_s
      [slice[0, part_size], (Cursor.encode(start + part_size) if slice.length > part_size)]
    end

    # Where a list or text continues from: the start, without a cursor.
    def self.offset(cursor)
      return 0 if cursor.nil? || cursor.to_s.empty?
      position = Cursor.decode(cursor, count: 1).first
      raise Cursor::Invalid unless position.is_a?(Integer) && !position.negative?
      position
    end
  end
end
