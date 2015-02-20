module QuickFile

  module Storage

    def self.build_for_connection(opts)
      kls = case opts[:provider].to_sym
            when :s3
              QuickFile::Storage::S3Storage
            when :ceph
              QuickFile::Storage::CephStorage
            when :local
              QuickFile::Storage::LocalStorage
            end
      kls.new(opts)
    end

    class StorageBase

      def initialize(opts)
        @options = opts
        @provider = @options[:provider].to_sym
        @interface = nil
        @bucket = nil

      end

      def interface
        @interface
      end

      def store(opts)
      end
      
      def delete(key)
      end

      def rename(old_key, new_key)
      end

      def get(key)
      end

      def download(key, to_file)
        self.get(key).download(to_file)
      end

      def value(key)
        self.get(key).value
      end

    end


    class ObjectBase
      def initialize(src, storage)
        @source = src
        @storage = storage
      end
      def source
        @source
      end
      def storage
        @storage
      end

      def read
      end
      def value
        self.read
      end
      def stream
      end
      def download
      end
      def content_type
      end
      def etag
      end
      def metadata
      end

    end

  end

end
