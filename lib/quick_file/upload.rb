require 'open-uri'

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
		FILE_CATEGORIES = {:none => 0, :image => 1, :video => 2, :file => 3}

    included do
      cattr_accessor :processes
      self.processes = {}

    end

    module ClassMethods
      def add_style(style_name, blk)
        processes[style_name.to_s] = {:blk => blk}
      end

			def quick_file_mongomapper_keys!
        key :sta, Integer    # state
        key :orf, String    # original filename
        key :sty, Hash      # styles
        key :sto, String, :default => "s3"    # storage
        key :oty, String    # owner type
        key :oid, ObjectId  # owner id
        key :err, Array     # errors

        attr_alias :state, :sta
        attr_alias :original_filename, :orf
        attr_alias :styles, :sty
        attr_alias :storage_type, :sto
        attr_alias :error_log, :err
        attr_alias :owner_type, :oty
			end

			def quick_file_mongoid_keys!
        field :sta, as: :state, type: Integer    # state
        field :orf, as: :original_filename, type: String    # original filename
        field :sty, as: :styles, type: Hash, default: {}      # styles
        field :sto, as: :storage_type, type: Integer    # storage
        field :oty, as: :owner_type, type: String    # owner type
        field :oid, as: :owner_id, type: Moped::BSON::ObjectId  # owner id
        field :err, as: :error_log, type: Array     # errors
			end
    end

    def owner=(obj)
      self.oty = obj.class.to_s
      self.oid = obj.id
    end

    def uploaded_file=(uf)
      self.error_log = []
      @uploaded_file = uf
      self.original_filename = uf.original_filename
      self.state! :loaded
      cache!
    end

    def linked_file=(url)
      self.error_log = []
      @linked_url = url
      self.original_filename = url.split('/').last
      self.state! :loaded
      save
    end

    def local_file=(fn)
      self.error_log = []
      @local_file = fn
      self.original_filename = fn.split('/').last
      self.state! :loaded
      cache!
    end

    def load_from_string(str, name)
      self.error_log = []
      @string_file = str
      self.original_filename = name
      self.state! :loaded
      cache!
    end

    def state?(val)
      self.state == STATES[val.to_sym]
    end

    def state!(val)
      self.state = STATES[val.to_sym]
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
      return unless state? :loaded
      if @uploaded_file
        cp = save_cache_file(QuickFile.generate_cache_name(extension), @file)
      elsif @linked_url
        # download file to 
        cp = download_cache_file(QuickFile.generate_cache_name(extension), @linked_url)
      elsif @local_file
        cp = copy_cache_file(QuickFile.generate_cache_name(extension), @local_file)
      elsif @string_file
        cp = write_to_cache_file(QuickFile.generate_cache_name(extension), @string_file)
      end
      self.styles["original"] = {
        "cache" => cp, 
        "ct" => QuickFile.content_type_for(cp),
        "sz" => File.size(cp)
      }
      self.validate!
      if self.error_log.size > 0
        self.state! :error
        File.delete(cp)
      else
        self.state! :cached
      end
      self.save
    end

    def validate!
      # implement in base class to perform validations
    end

    def save_cache_file(cn, file)
      Dir.mkdir QuickFile::CACHE_DIR unless File.directory?(QuickFile::CACHE_DIR)
      cp = QuickFile.cache_path(cn)
      File.open(cp, "wb") { |f| f.write(file.read) }
      return cp
    end

    def copy_cache_file(cn, fn)
      Dir.mkdir QuickFile::CACHE_DIR unless File.directory?(QuickFile::CACHE_DIR)
      cp = QuickFile.cache_path(cn)
      FileUtils.copy(fn, cp)
      return cp
    end

    def download_cache_file(cn, url)
      Dir.mkdir QuickFile::CACHE_DIR unless File.directory?(QuickFile::CACHE_DIR)
      cp = QuickFile.cache_path(cn)
      QuickFile.download(url, cp)
      return cp
    end

    def write_to_cache_file(cn, str)
      Dir.mkdir QuickFile::CACHE_DIR unless File.directory?(QuickFile::CACHE_DIR)
      cp = QuickFile.cache_path(cn)
      File.open(cp, "w") { |f| f.write(str) }
      return cp
    end

    def process!
      cache! if state? :loaded
      return unless state? :cached
      self.state! :processing
      self.save
      begin
        #puts "#{processes.size} processes"
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
        self.state! :processed
      rescue Exception => e
        puts e.message
        puts e.backtrace.join("\n\t")
        self.error_log << "PROCESS: #{e.message}"
        self.state! :error
      end

      self.save
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
      cache! if state? :loaded
      process! if state? :cached
      return unless state? :processed
      self.storage_type = STORAGE_TYPES[QuickFile.options[:connection][:provider].to_sym]if self.storage_type.nil?
      begin
        self.styles.keys.each do |style_name|
          store_style! style_name unless styles[style_name]["cache"].nil?
        end
        self.state = STATES[:stored]
      rescue StandardError => e
        puts e.message
        puts e.backtrace.join("\n\t")
        self.error_log << "STORE: #{e.message}"
        if self.error_log.count < 5
          self.store!
        else
          self.state! :error
        end
      end
      save
    end

    def storage_protocol
      case storage_type.to_i
      when STORAGE_TYPES[:aws]
        return :fog
      when STORAGE_TYPES[:local]
        return :fog
      when STORAGE_TYPES[:ceph]
        return :fog
      end
    end

    def storage_path(style_name, ext)
      # override in base class
      "#{style_name.to_s}/#{self.sanitized_basename}#{ext}"
    end

    def store_style!(style_name)
      fn = styles[style_name]["cache"]
      sp = storage_path(style_name, File.extname(fn))
      QuickFile.storage.store({
        :body => File.open(fn).read,
        :content_type => QuickFile.content_type_for(fn),
        :key => sp,
        :public => QuickFile.options[:fog_public]
      })
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
      style_name ||= "original"
      return default_url(style_name) unless (styles[style_name] && styles[style_name]["path"])
      "#{QuickFile.host_url[self.storage_type.to_i]}#{styles[style_name]["path"]}"
    end

    def download(style_name, to_file)
      QuickFile.storage.download(self.path(style_name), to_file)
    end

    def value(style_name)
      QuickFile.storage.value(self.path(style_name))
    end

    def delete_files
      # delete uploaded files
      styles.each do |k,v|
        QuickFile.storage.delete(v["path"]) if v["path"]
        File.delete(v["cache"]) if (v["cache"] && File.exists?(v["cache"]))
      end
      self.state = STATES[:deleted]
      save
    end

    def file_category
      if self.state.nil?
        return FILE_CATEGORIES[:none]
      elsif self.is_image?
        return FILE_CATEGORIES[:image]
      elsif self.is_video?
        return FILE_CATEGORIES[:video]
      else
        return FILE_CATEGORIES[:file]
      end
    end

    def url_hash
      ret = {}
      processes.keys.each do |style_name|
        ret[style_name] = self.url(style_name.to_sym)
      end
      ret
    end
    
  end

end

