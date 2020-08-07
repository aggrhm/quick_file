module QuickFile

  module Storage

    def self.build_for_connection(opts)
      kls = case opts[:provider].to_sym
            when :s3
              QuickFile::Storage::S3Storage
            when :swift
              QuickFile::Storage::SwiftStorage
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
      def options
        @options
      end
      def name
        @options[:name]
      end
      def default_when_blank?
        @options[:default_when_blank] == true
      end
      def primary?
        @options[:primary] == true
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

      def portal_url_for_key(key)
        self.options[:portal_url] + key
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
      def size
      end
      def etag
      end
      def metadata
      end

    end

  end

end
