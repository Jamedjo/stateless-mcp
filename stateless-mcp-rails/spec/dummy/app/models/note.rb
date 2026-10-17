# Notes kept in memory, standing in for an app's own records.
class Note
  attr_reader :id, :title, :body, :tags, :created_at

  def self.all
    store.sort_by { |note| [note.created_at, note.id] }.reverse
  end

  def self.find(id)
    store.find { |note| note.id == id }
  end

  def self.create!(title:, body: "", tags: [], created_at: Time.current)
    new(id: store.size + 1, title: title, body: body, tags: tags, created_at: created_at).tap { |note| store << note }
  end

  def self.delete_all
    store.clear
  end

  def self.store
    @store ||= []
  end

  def initialize(id:, title:, body:, tags:, created_at:)
    @id = id
    @title = title
    @body = body
    @tags = tags
    @created_at = created_at
  end
end
