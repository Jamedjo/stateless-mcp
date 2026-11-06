module StatelessMcp
  module OAuth
    # A client_id that is the URL of its client metadata document, checked
    # before anything is fetched from it.
    module ClientId
      MAX_LENGTH = 255

      # draft-ietf-oauth-client-id-metadata-document section 3 requires https
      # and a path, with no dot segments, fragment or credentials. A port is
      # refused too, even an explicit :443. Otherwise a client_id could aim the
      # fetch at another service on the same host.
      def self.check!(client_id)
        uri = parse(client_id)
        refuse("client_id must be the https URL of a client metadata document") unless uri.is_a?(URI::HTTPS) && uri.host && !uri.host.empty?
        refuse("client_id must be a URL with a path") unless uri.path.length > 1
        refuse("client_id must not have a fragment, credentials or a port") if uri.fragment || uri.userinfo || client_id.match?(%r{\Ahttps://[^/]*:}i)
        refuse("client_id must not have . or .. segments") if uri.path.split("/").intersect?([".", ".."])
        client_id
      end

      def self.parse(client_id)
        URI.parse(client_id) if client_id.is_a?(String) && client_id.length <= MAX_LENGTH
      rescue URI::InvalidURIError
        nil
      end

      def self.refuse(message)
        raise Error.new("invalid_client", message, redirectable: false)
      end

      private_class_method :parse, :refuse
    end
  end
end
