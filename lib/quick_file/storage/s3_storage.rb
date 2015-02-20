require 'aws-sdk'

module QuickFile

  module Storage

    class S3Storage < StorageBase

      def initialize(opts)
        super(opts)
        conn_opts = {
          :use_ssl       => ( @options[:use_ssl].nil? ? false : @options[:use_ssl] ),
          :access_key_id     => @options[:access_key_id],
          :secret_access_key => @options[:secret_access_key]
        }
        #conn_opts[:use_ssl] = @options[:use_ssl] if @options[:use_ssl]
        @interface = AWS::S3.new(conn_opts)

        self.set_bucket(@options[:directory])
      end

      def set_bucket(bucket_name)
        @bucket_name = bucket_name

        @bucket = @interface.buckets[@bucket_name] || @interface.buckets.create(@bucket_name)
      end

      def store(opts)
        write_opts = {}
        write_opts[:acl] = :public_read if @options[:public] == true
        write_opts[:content_type] = opts[:content_type] if opts[:content_type]
        @bucket.objects[opts[:key]].write(opts[:body], write_opts)
      end

      def delete(key)
        @bucket.objects[key].delete
      end

      def rename(old_key, new_key)
        obj = @bucket.objects[old_key]
        opts = {}
        opts[:acl] = :public_read if @options[:public] == true
        obj.move_to(new_key, opts)
        return obj
      end

      def get(key)
        obj = @bucket.objects[key]
        return nil if !obj.exists?
        return S3StorageObject.new(obj, self) 
      end

    end

    class S3StorageObject < ObjectBase
      def read
        @source.read
      end
      def stream(&block)
        @source.read(&block)
      end
      def download(path)
        open(path, 'wb') do |file|
          @source.read do |chunk|
            file.write(chunk)
          end
        end
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
