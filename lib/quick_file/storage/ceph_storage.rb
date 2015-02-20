require 'right_aws'

module QuickFile

  module Storage

    class CephStorage < StorageBase

      def initialize(opts)
        super(opts)
        use_ssl = @options[:use_ssl] || false
        port = use_ssl ? 443 : 80
        proto = use_ssl ? 'https' : 'http'
        @interface = RightAws::S3.new(@options[:access_key_id], @options[:secret_access_key], {:server => @options[:host], :port => port, :protocol => proto, :no_subdomains => true})

        self.set_bucket(@options[:directory])

      end

      def set_bucket(bucket_name)
        @bucket_name = bucket_name
        @bucket = @interface.bucket(@bucket_name) || @interface.bucket(@bucket_name, true)
      end

      def store(opts)
        @bucket.put(opts[:key], opts[:body])
      end

      def delete(key)
        @bucket.key(key).delete
      end

      def get(key)
        CephStorageObject.new(@bucket.get(key), self)
      end

    end

    class CephStorageObject < ObjectBase
      def read
        @bucket.get(key)
      end
      def download(path)
        open(path, 'wb') do |file|
          file.write @source
        end
      end

    end

  end

end
