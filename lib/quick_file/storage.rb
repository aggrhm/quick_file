require 'aws/s3'

module QuickFile
  class Storage
    def initialize(opts)
      @options = opts
      @provider = @options[:provider].to_sym

      if @provider == :local
        # prepare for local storage access
      else
        conn_opts = {
          :server            => @options[:server],
          :access_key_id     => @options[:access_key_id],
          :secret_access_key => @options[:secret_access_key]
        }
        conn_opts[:use_ssl] = @options[:use_ssl] if @options[:use_ssl]
        AWS::S3::Base.establish_connection!(conn_opts)
      end
            
    end

    def is_provider?(types)
      types.include? @provider
    end

    def set_bucket(bucket)
      @bucket_name = bucket

      if is_provider? [:ceph, :s3]
        AWS::S3::Bucket.create(@bucket_name)
      end
    end

    def store(opts)
      if is_provider? [:ceph, :s3]

        AWS::S3::S3Object.store(opts[:key], opts[:body], @bucket_name, :content_type => opts[:content_type])

      elsif is_provider? [:local]

        path = local_path(opts[:key])
        FileUtils.mkdir_p File.dirname(path)
        open(path, 'w') {|file| file.write(opts[:body])}

      end
    end

    def delete(key)
      if is_provider? [:ceph, :s3]
        AWS::S3::S3Object.delete(key, @bucket_name)
      elsif is_provider? [:local]
        File.delete(local_path(key))
      end
    end

    def download(key, to_file)
      if is_provider? [:ceph, :s3]
        open(to_file, 'w') do |file|
          val = AWS::S3::S3Object.value(key, @bucket_name)
          file.write(val)
          end
        end
      elsif is_provider? [:local]
        open(to_file, 'w') do |file|
          file.write(File.open(local_path(key)).read)
        end
      end
    end

    def value(key)
      if is_provider? [:ceph, :s3]
        return AWS::S3::S3Object.value(key, @bucket_name)
      elsif is_provider? [:local]
        File.open(local_path(key)).read
      end
    end

    def local_path(key)
      File.join(@options[:local_root], @bucket_name, key)
    end

  end
end
