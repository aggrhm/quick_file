module QuickFile

  module Upload
    extend ActiveSupport::Concern

    ## 
    #   required fields: id, state, original_filename, styles
    #   steps
    #     1. cache
    #     2. process
    #     3. store

    STATES = {:loaded => 0, :cached => 1, :processing => 2, :processed => 3, :storing => 4, :stored => 5, :deleted => 6, :error => 7}

    included do
      cattr_accessor :processes
      self.processes = {}

    end

    module ClassMethods
      def add_style(style_name, blk)
        processes[style_name.to_s] = {:blk => blk}
      end
    end

    module InstanceMethods
      def initialize
        @file = nil
        styles = {}
        errors = []
      end

      def uploaded_file=(uf)
        errors = []
        @file = uf
        self.original_filename = uf.original_filename
        self.state = STATES[:loaded]
        cache!
      end

      def loaded?
        self.state == STATES[:loaded]
      end

      def cached?
        self.state == STATES[:cached]
      end

      def processed?
        self.state == STATES[:processed]
      end

      def stored?
        self.state == STATES[:stored]
      end

      def error?
        self.state == STATES[:error]
      end

      def sanitized_basename
        File.basename original_filename.gsub( /[^a-zA-Z0-9_\-\.]/, '_'), File.extname(original_filename)
      end

      def sanitized_filename
        File.basename original_filename.gsub( /[^a-zA-Z0-9_\-\.]/, '_')
      end

      def extension
        File.extname(original_filename)
      end

      def cache!
        return unless loaded?
        cp = save_cache_file(QuickFile.generate_cache_name(extension), @file)
        styles["original"] = {"cache" => cp, 
                              "ct" => QuickFile.content_type_for(cp),
                              "sz" => File.size(cp)}
        self.validate!
        if errors.size > 0
          self.state = STATES[:error]
          File.delete(cp)
        else
          self.state = STATES[:cached]
        end
        self.save
      end

      def save_cache_file(cn, file)
        Dir.mkdir QuickFile::CACHE_DIR unless File.directory?(QuickFile::CACHE_DIR)
        cp = QuickFile.cache_path(cn)
        File.open(cp, "wb") { |f| f.write(file.read) }
        cp
      end

      def process!
        return unless cached?
        self.state = STATES[:processing]
        save
        begin
          puts "#{processes.size} processes"
          processes.each do |style_name, opts|
            puts "Processing #{style_name}..."
            fn = opts[:blk].call(styles["original"]["cache"])
            unless fn.nil?
              if (styles.key?(style_name) && !styles[style_name]["cache"].nil?)
                File.delete(styles[style_name]["cache"])
              end
              styles[style_name.to_s] = {"cache" => fn, 
                                         "ct" => QuickFile.content_type_for(fn),
                                         "sz" => File.size(fn)}
            end
          end
          self.state = STATES[:processed]
        rescue StandardError => e
          puts e.message
          self.errors << "PROCESS: #{e.message}"
          self.state = STATES[:error]
        end

        self.save

        store!
      end

      def reprocess!
        return unless (stored? || error?)
        # download original file
        cp = QuickFile.new_cache_file File.extname(self.path)
        QuickFile.download(url, cp)
        styles["original"] = {"cache" => cp, 
                              "ct" => QuickFile.content_type_for(cp),
                              "sz" => File.size(cp)}
        self.state = STATES[:cached]
        self.save
        self.process!
      end

      def add_file!(style_name, path)
        styles[style_name.to_s] = {"path" => path}
        get_style(style_name.to_s)
        self.state = STATES[:stored]
        save
      end

      def path(style_name=nil)
        style_name ||= :original
        styles[style_name.to_s]["path"]
      end

      def content_type(style_name=nil)
        style_name ||= :original
        styles[style_name.to_s]["ct"]
      end

      def size(style_name=nil)
        style_name ||= :original
        styles[style_name.to_s]["sz"]
      end

      def is_image?(style_name=nil)
        style_name ||= :original
        return false if content_type(style_name).nil?
        content_type(style_name).include? "image"
      end

      def is_video?(style_name=nil)
        style_name ||= :original
        fp = styles[style_name]["path"] || styles[style_name]["cache"]
        QuickFile.is_video_file? fp
      end

      def style_exists?(style_name)
        !styles[style_name.to_s].nil?
      end

      def store!
        return unless processed?
        begin
          styles.keys.each do |style_name|
            store_style! style_name unless styles[style_name]["cache"].nil?
          end
          self.state = STATES[:stored]
        rescue StandardError => e
          puts e.message
          self.errors << "STORE: #{e.message}"
          if self.errors.count < 5
            self.store!
          else
            self.state = STATES[:error]
          end
        end
        save
      end

      def storage_protocol
        case storage_type.to_sym
        when :s3
          return :fog
        when :fog
          return :fog
        end
      end

      def store_style!(style_name)
        fn = styles[style_name]["cache"]
        sp = storage_path(style_name, File.extname(fn))
        if storage_protocol == :fog
          QuickFile.fog_directory.files.create({
            :body => File.open(fn).read,
            :content_type => QuickFile.content_type_for(fn),
            :key => sp,
            :public => QuickFile.options[:fog_public]
          })
        end
        styles[style_name]["path"] = sp
        styles[style_name]["ct"] = QuickFile.content_type_for(fn)
        styles[style_name]["sz"] = File.size(fn)
        styles[style_name].delete("cache")
        File.delete(fn)

        save
      end

      def get_style(style_name)
        fn = path(style_name)
        if storage_protocol == :fog
          f = QuickFile.fog_directory.files.get(fn)
          if f.nil?
            styles[style_name]["ct"] = QuickFile.content_type_for(fn)
            styles[style_name]["sz"] = 0
          else
            styles[style_name]["ct"] = f.content_type.nil? ? QuickFile.content_type_for(fn) : f.content_type
            styles[style_name]["sz"] = f.content_length
          end
          save
        end
        f
      end

      def url(style_name=nil, opts={:secure=>true})
        proto = opts[:secure] ? "https://" : "http://"
        style_name ||= "original"
        return default_url(style_name) unless (styles[style_name] && styles[style_name]["path"])
        "#{proto}#{QuickFile.host_url[storage_type.to_sym]}#{styles[style_name]["path"]}"
      end

      def delete
        # delete uploaded files
        styles.each do |k,v|
          QuickFile.fog_directory.files.new(:key => v["path"]).destroy if v["path"]
          File.delete(v["cache"]) if (v["cache"] && File.exists?(v["cache"]))
        end
        self.state = STATES[:deleted]
      end
    end

  end
end
