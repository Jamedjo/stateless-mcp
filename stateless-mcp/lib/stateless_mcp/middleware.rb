module StatelessMcp
  # Rack middleware for one server's endpoint. A POST to the server's path has
  # its body read within the server's limit and its headers checked against
  # the body; the app then finds the server in env[Server::ENV_KEY] and the
  # parsed body in env[REQUEST_ENV_KEY]. Requests to other paths pass through
  # untouched.
  #
  #   use StatelessMcp::Middleware, server: StatelessMcp::Server.new(path: "/mcp")
  #
  # Authentication, rate limits and the Origin check are the app's, so
  # middleware doing them goes before this one: a request it refuses is then
  # never read.
  class Middleware
    def initialize(app, server:)
      raise ArgumentError, "server: must be a StatelessMcp::Server; got #{server.inspect}" unless server.is_a?(Server)
      @app = app
      @server = server
    end

    def call(env)
      return @app.call(env) unless @server.endpoint?(env)
      env[Server::ENV_KEY] = @server
      return method_not_allowed if ["GET", "DELETE"].include?(env["REQUEST_METHOD"])
      return @app.call(env) unless env["REQUEST_METHOD"] == "POST"
      body = env[REQUEST_ENV_KEY] = RequestBody.read(env, max_bytes: @server.max_body_bytes)
      check(env, body)
      @app.call(env)
    rescue Refusal => refusal
      refusal.to_rack(env[REQUEST_ENV_KEY])
    end

    private

    # Every request is held to 2026-07-28. Serving earlier protocol revisions
    # means deciding here which rules a request is held to.
    def check(env, body)
      HeaderCheck.check!(env, body)
    end

    # Clients on earlier revisions open a stream with GET and end a session
    # with DELETE; the spec has a stateless server answer both with 405.
    def method_not_allowed
      [405, { "allow" => "POST" }, []]
    end
  end
end
