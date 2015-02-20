module QuickFile

  module Storage

    class CephStorage < StorageBase

      def initialize(opts)
        super(opts)

        @bucket_name = bucket
      end

      def store(opts)
        path = local_path(opts[:key])
        FileUtils.mkdir_p File.dirname(path)
        open(path, 'w') {|file| file.write(opts[:body])}
      end

      def delete(key)
        File.delete(local_path(key))
      end

      def get(key)
        path = local_path(key)
        if File.exists?(path)
          return LocalStorageObject.new(path, self)
        else
          return nil
        end
      end

      def local_path(key)
        File.join(@options[:local_root], @bucket_name, key)
      end

    end

    class LocalStorageObject < ObjectBase
      def read
        File.open(@source).read
      end
      def download(path)
        open(path, 'wb') do |file|
          file.write self.read
        end
      end
      def content_type
        QuickFile.content_type_for(@source)
      end

    end

  end

end
