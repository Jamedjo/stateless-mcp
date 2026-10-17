module StatelessMcp
  # A request turned away before it reaches the app, answered as a JSON-RPC
  # error.
  class Refusal < StandardError
    attr_reader :code, :data

    def initialize(code, message, data: nil)
      super(message)
      @code = code
      @data = data
    end

    def to_rack(body)
      id = body["id"] if body.is_a?(Hash)
      [Rpc.status_for(code), { "content-type" => "application/json" }, [JSON.generate(Rpc.error(id, code, message, data: data))]]
    end
  end
end
