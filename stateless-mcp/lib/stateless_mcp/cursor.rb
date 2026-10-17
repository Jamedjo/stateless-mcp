module StatelessMcp
  # Cursors are opaque to the client, so a model carries next_cursor forward
  # rather than inventing positions of its own. Inside, a cursor is a JSON
  # array of values in URL-safe base64.
  module Cursor
    # Raised for a cursor this library didn't issue.
    Invalid = Class.new(StandardError)

    def self.encode(*values)
      Base64.urlsafe_encode64(JSON.generate(values), padding: false)
    end

    # The values encoded, as an array of exactly count of them when count is given.
    def self.decode(cursor, count: nil)
      values = JSON.parse(Base64.urlsafe_decode64(cursor.to_s))
      raise Invalid unless values.is_a?(Array) && (count.nil? || values.size == count)
      values
    rescue ArgumentError, EncodingError, JSON::ParserError
      raise Invalid
    end
  end
end
