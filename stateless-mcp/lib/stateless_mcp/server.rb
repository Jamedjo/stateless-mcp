module StatelessMcp
  # One MCP endpoint: where it is served, how it describes itself, and the
  # limits it holds requests to. Every other part of the library is handed the
  # server it serves, so an app can run several side by side:
  #
  #   admin = StatelessMcp::Server.new(path: "/admin/mcp", name: "admin", max_body_bytes: 16_384)
  #
  # A server is frozen once built, so it can be shared between threads.
  class Server
    # Raised for a setting that can't be served, naming the setting.
    Invalid = Class.new(ArgumentError)

    # The server a request was routed to, which the middleware leaves in the Rack env.
    ENV_KEY = "stateless_mcp.server"

    # How a resource's tools are named from its actions: index on notes is list_notes.
    DEFAULT_TOOL_VERBS = { index: "list", show: "get", create: "create", update: "update", destroy: "delete" }.freeze

    DEFAULTS = {
      path: "/mcp",
      name: "mcp",
      version: "1.0.0",
      title: nil,
      instructions: nil,
      max_body_bytes: 1_048_576,
      page_size: 20,
      max_page_size: 100,
      tool_verbs: DEFAULT_TOOL_VERBS,
      # The MCP spec has servers refuse a request whose Origin header names
      # another site, so a page in a browser can't drive the tools with the
      # visitor's credentials. Requests without an Origin, from non-browser
      # clients, are unaffected.
      check_origin: true,
      # Origins other than the server's own that may call it, such as
      # "https://app.example".
      allowed_origins: []
    }.freeze

    attr_reader(*DEFAULTS.keys)

    # tool_verbs are merged over the defaults, so an app can rename one verb
    # without restating the rest.
    def initialize(**settings)
      unknown = settings.keys - DEFAULTS.keys
      raise Invalid, "Unknown server settings: #{unknown.join(", ")}" if unknown.any?
      settings = DEFAULTS.merge(settings.compact)
      @path = check_path(settings[:path])
      @name = check_text(:name, settings[:name])
      @version = check_text(:version, settings[:version])
      @title = check_text(:title, settings[:title]) unless settings[:title].nil?
      @instructions = check_text(:instructions, settings[:instructions]) unless settings[:instructions].nil?
      @max_body_bytes = check_positive(:max_body_bytes, settings[:max_body_bytes])
      @page_size = check_positive(:page_size, settings[:page_size])
      @max_page_size = check_positive(:max_page_size, settings[:max_page_size])
      raise Invalid, "page_size (#{page_size}) can't be larger than max_page_size (#{max_page_size})" if page_size > max_page_size
      @tool_verbs = check_tool_verbs(settings[:tool_verbs])
      @check_origin = check_boolean(:check_origin, settings[:check_origin])
      @allowed_origins = check_origins(settings[:allowed_origins])
      freeze
    end

    # Whether a request is addressed to this server's endpoint.
    def endpoint?(env)
      env["PATH_INFO"] == path
    end

    # Whether a request's Origin header, if it has one, may call this server:
    # the server's own origin, or one of allowed_origins.
    def origin_allowed?(env)
      origin = env["HTTP_ORIGIN"]
      return true if origin.nil? || !check_origin
      origin = origin.downcase
      origin == Rack::Request.new(env).base_url.downcase || allowed_origins.include?(origin)
    end

    # The serverInfo object the protocol describes a server with.
    def info
      { name: name, title: title, version: version }.compact
    end

    def inspect
      "#<#{self.class.name} #{path} #{name}>"
    end

    private

    def check_path(value)
      return value.dup.freeze if value.is_a?(String) && value.match?(%r{\A/[^?#\s]*\z}) && (value == "/" || !value.end_with?("/"))
      raise Invalid, "path must be an absolute path such as \"/mcp\", without a trailing slash, query or fragment; got #{value.inspect}"
    end

    def check_text(setting, value)
      return value.dup.freeze if value.is_a?(String) && !value.strip.empty?
      raise Invalid, "#{setting} must be a non-empty string; got #{value.inspect}"
    end

    def check_positive(setting, value)
      return value if value.is_a?(Integer) && value.positive?
      raise Invalid, "#{setting} must be a positive integer; got #{value.inspect}"
    end

    def check_boolean(setting, value)
      return value if value == true || value == false
      raise Invalid, "#{setting} must be true or false; got #{value.inspect}"
    end

    def check_origins(value)
      raise Invalid, "allowed_origins must be an array of origins such as \"https://app.example\"; got #{value.inspect}" unless value.is_a?(Array)
      value.map { |origin| check_origin_url(origin) }.freeze
    end

    # Only scheme, host and port: an Origin header carries nothing more.
    def check_origin_url(value)
      uri = URI.parse(value.to_s)
      return value.downcase.freeze if uri.is_a?(URI::HTTP) && uri.host && !uri.host.empty? && uri.path.empty? && uri.query.nil? && uri.fragment.nil? && uri.userinfo.nil?
      raise Invalid, "allowed_origins entries must be origins such as \"https://app.example\", without a path; got #{value.inspect}"
    rescue URI::InvalidURIError
      raise Invalid, "allowed_origins entries must be origins such as \"https://app.example\", without a path; got #{value.inspect}"
    end

    def check_tool_verbs(value)
      raise Invalid, "tool_verbs must be a hash of action to verb; got #{value.inspect}" unless value.is_a?(Hash)
      verbs = DEFAULT_TOOL_VERBS.merge(value.to_h { |action, verb| [action.to_sym, verb] })
      verbs.each { |action, verb| check_text(:"tool_verbs[:#{action}]", verb) }
      verbs.transform_values { |verb| verb.dup.freeze }.freeze
    end
  end
end
