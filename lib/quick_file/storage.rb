require 'aws-sdk'

module QuickFile
  class Storage
    def initialize(opts)
      @options = opts
      @provider = @options[:provider].to_sym
      @interface = nil
      @bucket = nil

      if @provider == :local
        # prepare for local storage access
      else
        conn_opts = {
          :s3_endpoint       => @options[:host],
          :s3_port       => ( @options[:use_ssl] ? 443 : 80 ),
          :access_key_id     => @options[:access_key_id],
          :secret_access_key => @options[:secret_access_key]
        }
        #conn_opts[:use_ssl] = @options[:use_ssl] if @options[:use_ssl]
        @interface = AWS::S3.new(conn_opts)
      end
            
    end

    def is_provider?(types)
      types.include? @provider
    end

    def interface
      @interface
    end

    def set_bucket(bucket)
      @bucket_name = bucket

      if is_provider? [:ceph, :s3]
        @bucket = @interface.buckets[@bucket_name] || @interface.buckets.create(@bucket_name)
      end
    end

    def store(opts)
      if is_provider? [:ceph, :s3]

        #AWS::S3::S3Object.store(opts[:key], opts[:body], @bucket_name, :content_type => opts[:content_type])
        @bucket.objects[opts[:key]].write(opts[:body])

      elsif is_provider? [:local]

        path = local_path(opts[:key])
        FileUtils.mkdir_p File.dirname(path)
        open(path, 'w') {|file| file.write(opts[:body])}

      end
    end

    def delete(key)
      if is_provider? [:ceph, :s3]
        #AWS::S3::S3Object.delete(key, @bucket_name)
        @bucket.objects[key].delete
      elsif is_provider? [:local]
        File.delete(local_path(key))
      end
    end

    def download(key, to_file)
      if is_provider? [:ceph, :s3]
        open(to_file, 'wb') do |file|
          @bucket.objects[key].read do |chunk|
            file.write(chunk)
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
        return @bucket.objects[key].read
        #return AWS::S3::S3Object.value(key, @bucket_name)
      elsif is_provider? [:local]
        File.open(local_path(key)).read
      end
    end

    def local_path(key)
      File.join(@options[:local_root], @bucket_name, key)
    end

  end
end
