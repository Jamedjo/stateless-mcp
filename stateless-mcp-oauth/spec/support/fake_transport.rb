require "json"

# Stands in for a client's host. The block returns the document for a URL, as
# a Hash or a String, or nil for a 404. It records each URL asked for.
class FakeTransport
  attr_reader :fetched

  def initialize(cache_control: nil, &documents)
    @cache_control = cache_control
    @documents = documents
    @fetched = []
  end

  def call(url, headers:, timeout:)
    @fetched << url
    document = @documents.call(url)
    body = document.is_a?(Hash) ? JSON.generate(document) : document.to_s
    yield document ? 200 : 404, { "content-type" => "application/json", "cache-control" => @cache_control }.compact, [body]
  end
end
