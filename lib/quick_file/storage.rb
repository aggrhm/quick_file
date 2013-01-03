require 'aws/s3'

module QuickFile
  class Storage
    def initialize(opts)
      @options = opts
      @provider = @options[:provider].to_sym

      if @provider == :local
        # prepare for local storage access
      else
        AWS::S3::Base.establish_connection!(
                :server            => @options[:server],
                :use_ssl           => true,
                :access_key_id     => @options[:access_key_id],
                :secret_access_key => @options[:secret_access_key]
        )
      end
            
    end

    def is_provider?(types)
      types.include? @provider
    end

    def set_bucket(bucket)
      @bucket_name = bucket

      if is_provider? [:ceph, :s3]
        bucket = AWS::S3::Bucket.find('my-new-bucket')
        if bucket.nil?
          AWS::S3::Bucket.create('my-new-bucket')
        end
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
      open(to_file, 'w') do |file|
        if is_provider? [:ceph, :s3]
          AWS::S3::S3Object.stream(key, @bucket_name) do |chunk|
            file.write(chunk)
          end
        elsif is_provider? [:local]
          file.write(File.open(local_path(key)).read)
        end
      end
    end

    def local_path(key)
      File.join(@options[:local_root], @bucket_name, key)
    end

  end
end
