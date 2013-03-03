require 'aws-sdk'
require 'right_aws'

module QuickFile
  class Storage
    def initialize(opts)
      @options = opts
      @provider = @options[:provider].to_sym
      @interface = nil
      @bucket = nil

      if @provider == :local
        # prepare for local storage access
      elsif @provider == :s3
        conn_opts = {
          :use_ssl       => ( @options[:use_ssl].nil? ? false : @options[:use_ssl] ),
          :access_key_id     => @options[:access_key_id],
          :secret_access_key => @options[:secret_access_key]
        }
        #conn_opts[:use_ssl] = @options[:use_ssl] if @options[:use_ssl]
        @interface = AWS::S3.new(conn_opts)
      elsif @provider == :ceph
        use_ssl = @options[:use_ssl] || false
        port = use_ssl ? 443 : 80
        proto = use_ssl ? 'https' : 'http'
        @interface = RightAws::S3.new(@options[:access_key_id], @options[:secret_access_key], {:server => @options[:host], :port => port, :protocol => proto, :no_subdomains => true})
      end
      self.set_bucket(@options[:directory]) if @options[:directory]
            
    end

    def is_provider?(types)
      types.include? @provider
    end

    def interface
      @interface
    end

    def set_bucket(bucket)
      @bucket_name = bucket

      if is_provider? [:s3]
        @bucket = @interface.buckets[@bucket_name] || @interface.buckets.create(@bucket_name)
      elsif is_provider? [:ceph]
        @bucket = @interface.bucket(@bucket_name) || @interface.bucket(@bucket_name, true)
      end
    end

    def store(opts)
      if is_provider? [:s3]
        #AWS::S3::S3Object.store(opts[:key], opts[:body], @bucket_name, :content_type => opts[:content_type])
        write_opts = {}
        write_opts[:acl] = :public_read if @options[:public] == true
        write_opts[:content_type] = opts[:content_type] if opts[:content_type]
        @bucket.objects[opts[:key]].write(opts[:body], write_opts)
      elsif is_provider? [:ceph]
        @bucket.put(opts[:key], opts[:body])
      elsif is_provider? [:local]

        path = local_path(opts[:key])
        FileUtils.mkdir_p File.dirname(path)
        open(path, 'w') {|file| file.write(opts[:body])}

      end
    end

    def delete(key)
      if is_provider? [:s3]
        #AWS::S3::S3Object.delete(key, @bucket_name)
        @bucket.objects[key].delete
      elsif is_provider? [:ceph]
        @bucket.key(key).delete
      elsif is_provider? [:local]
        File.delete(local_path(key))
      end
    end

    def download(key, to_file)
      if is_provider? [:s3]
        open(to_file, 'wb') do |file|
          @bucket.objects[key].read do |chunk|
            file.write(chunk)
          end
        end
      elsif is_provider? [:ceph]
        open(to_file, 'wb') do |file|
          file.write @bucket.get(key)
        end
      elsif is_provider? [:local]
        open(to_file, 'w') do |file|
          file.write(File.open(local_path(key)).read)
        end
      end
    end

    def value(key)
      if is_provider? [:s3]
        return @bucket.objects[key].read
        #return AWS::S3::S3Object.value(key, @bucket_name)
      elsif is_provider? [:ceph]
        return @bucket.get(key)
      elsif is_provider? [:local]
        File.open(local_path(key)).read
      end
    end

    def local_path(key)
      File.join(@options[:local_root], @bucket_name, key)
    end

  end
end
