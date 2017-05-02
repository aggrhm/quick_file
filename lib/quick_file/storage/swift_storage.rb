require 'stacktor'

module QuickFile

  module Storage

    class SwiftStorage < StorageBase

      attr_accessor :auth_client, :swift_client, :container_name

      def initialize(opts)
        super(opts)
        ident_url = opts[:auth_url]
        if ident_url.include?("/v3")
          ident_client_class = Stacktor::Identity::V3::Client
        elsif ident_url.include?("/v2")
          ident_client_class = Stacktor::Identity::V2::Client
        else
          raise "Cannot determine proper client for url"
        end
        @auth_client = ident_client_class.new(url: opts[:auth_url])

        @swift_client = Stacktor::Swift::V1::Client.new
        @swift_client.before_request do |req_opts, client|
          if !client.has_valid_token?
            self.authenticate
          end
        end

        @interface = @swift_client

        self.set_container(@options[:container] || @options[:directory])

      end

      def authenticate
        resp = @auth_client.authenticate_token(@options)
        if resp[:success]
          token = resp[:token] # parse into ostruct-like object, can be extended
          @swift_client.token = token
          @swift_client.url = token.endpoint_url_for_service_type('object-store', :public)
          return true
        else
          raise "Could not authenticate with OpenStack: #{resp.inspect}"
        end
      end

      def set_container(name)
        @container_name = name
      end

      def store(opts)
        resp = @swift_client.create_object(container_name: @container_name, object_name: opts[:key], content: opts[:body], content_type: opts[:content_type])
        raise resp[:body] if resp[:success] != true
        return resp
      end

      def delete(key)
        resp = @swift_client.delete_object(container_name: @container_name, object_name: key)
        raise resp[:body] if resp[:success] != true
        return resp
      end

      def get(key)
        resp = @swift_client.get_object_metadata(container_name: @container_name, object_name: key)
        raise resp[:body] if resp[:success] != true
        SwiftStorageObject.new(resp[:object], self)
      end

    end

    class SwiftStorageObject < ObjectBase
      def read
        @source.read
      end
      def stream(&block)
        @source.stream(&block)
      end
      def download(path)
        @source.write_to_file(path)
      end
      def size
        @source.content_length
      end
      def content_type
        @source.content_type
      end
      def etag
        @source.etag
      end
      def metadata
        @source.metadata
      end

    end

  end

end
