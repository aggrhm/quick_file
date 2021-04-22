require 'aws-sdk'

module QuickFile

  module Storage

    class S3Storage < StorageBase

      def initialize(opts)
        super(opts)

        conn_opts = {
          region: @options[:region] || 'us-east-1',
          credentials: Aws::Credentials.new(@options[:access_key_id], @options[:secret_access_key])
        }
        @interface = Aws::S3::Resource.new(conn_opts)

        self.set_bucket(@options[:bucket] || @options[:directory])
      end

      def set_bucket(bucket_name)
        @bucket_name = bucket_name

        @bucket = @interface.bucket(bucket_name)
        if !@bucket.exists?
          @bucket.create
        end
        @bucket
      end

      def store(opts)
        write_opts = {}
        write_opts[:body] = opts[:body]
        write_opts[:acl] = 'public-read' if (@options[:public] == true || opts[:public] == true)
        write_opts[:content_type] = opts[:content_type] if opts[:content_type]
        @bucket.object(opts[:key]).put(write_opts)
      end

      def delete(key)
        @bucket.object(key).delete
      end

      def rename(old_key, new_key)
        obj = @bucket.object(old_key)
        new_obj = @bucket.object(new_key)
        opts = {}
        opts[:acl] = 'public-read' if @options[:public] == true
        obj.move_to(new_obj, opts)
        return obj
      end

      def get(key)
        obj = @bucket.object(key)
        return nil if !obj.exists?
        return S3StorageObject.new(obj, self) 
      end

    end

    class S3StorageObject < ObjectBase
      def read
        @source.get.body.read
      end
      def stream(&block)
        @source.get.body.read(&block)
      end
      def download(path)
        @source.get({response_target: path})
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
