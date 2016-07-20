require 'open-uri'
require 'digest/md5'

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
      cattr_accessor :processes, :helpers
      self.processes = {}
      self.helpers = {}
    end

    module ClassMethods
      # TODO: add ability to pass options hash with storage name as option
      def add_style(style_name, blk)
        processes[style_name.to_s] = {:blk => blk}
      end

      ##
      # Adds helper to be ran after item is cached to build profile.
      #
      # Example:
      # add_helper :exif, lambda {|upload, orig_file|
      #   if QuickFile.is_image_file?(orig_file)
      #     upload.profile['exif'] = QuickFile.extract_exif_data(orig_file)
      #   end
      # }
      def add_helper(helper_name, args={}, blk)
        args[:blk] = blk
        helpers[helper_name] = args
      end

      def quick_file_mongomapper_keys!
        key :sta, Integer    # state
        key :orf, String    # original filename
        key :sty, Hash      # styles
        key :oty, String    # owner type
        key :oid, ObjectId  # owner id
        key :err, Array     # errors
        key :cat, Integer   # file category
        key :prf, Hash      # profile
        key :mh, String     # md5_hash

        attr_alias :state, :sta
        attr_alias :original_filename, :orf
        attr_alias :styles, :sty
        attr_alias :error_log, :err
        attr_alias :owner_type, :oty
        attr_alias :profile, :prf
        attr_alias :md5_hash, :mh
      end

      def quick_file_mongoid_keys!
        field :sta, as: :state, type: Integer    # state
        field :orf, as: :original_filename, type: String    # original filename
        field :sty, as: :styles, type: Hash, default: {}      # styles
        field :oty, as: :owner_type, type: String    # owner type
        field :oid, as: :owner_id  # owner id
        field :err, as: :error_log, type: Array     # errors
        field :cat, type: Integer
        field :prf, as: :profile, type: Hash, default: {}
        field :mh, as: :md5_hash, type: String
      end

      def upload(src, opts={})
        upload = self.new
        upload.owner = opts[:owner] if opts[:owner]
        upload.source = src
        upload.store!
        if upload.state?(:stored)
          return {success: true, data: upload}
        else
          return {success: false, data: upload, error: upload.error_log[0] || "An error occurred processing the upload."}
        end
      end

      def cache(src, opts={})
        upload = self.new
        upload.owner = opts[:owner] if opts[:owner]
        upload.source = src
        if upload.state?(:cached)
          return {success: true, data: upload}
        else
          return {success: false, data: upload, error: upload.error_log[0] || "An error occurred processing the upload."}
        end
      end

    end

    ## ACCESSORS

    def owner=(obj)
      @owner = obj
      self.oty = obj.class.to_s
      self.oid = obj.id
    end

    def owner
      return nil if self.oty.nil? || self.oid.nil?
      @owner ||= begin
        self.oty.constantize.find(self.oid)
      end
    end

    def state?(val)
      self.state == STATES[val.to_sym]
    end

    def state!(val)
      self.state = STATES[val.to_sym]
    end

    def sanitized_basename
      File.basename original_filename.gsub( /[^a-zA-Z0-9_\-\.\@]/, '_'), File.extname(original_filename)
    end

    def sanitized_filename
      File.basename original_filename.gsub( /[^a-zA-Z0-9_\-\.\@]/, '_')
    end

    def extension
      File.extname(original_filename)
    end

    def storage_name(style_name=:original)
      styles[style_name.to_s]["stg"]
    end
    def storage(style_name=:original)
      QuickFile.storage_for(self.storage_name(style_name))
    end
    def storage_object(style_name=:original)
      self.storage.get(self.path(style_name))
    end

    def path(style_name=:original)
      return nil if styles[style_name.to_s].nil?
      styles[style_name.to_s]["path"]
    end

    def cache_path(style_name=:original)
      return nil if styles[style_name.to_s].nil?
      styles[style_name.to_s]["cache"]
    end

    def default_url(style_name=:original)
      nil
    end

    def url(style_name=:original, opts={:secure=>true})
      if p = path(style_name)
        return "#{self.storage(style_name).options[:portal_url]}#{p}"
      elsif (p = cache_path(style_name)) && (purl = QuickFile.storage_for(:cache).options[:portal_url])
        return "#{purl}#{File.basename(p)}"
      else
        return default_url(style_name)
      end
    end

    def value(style_name)
      self.storage.value(self.path(style_name))
    end

    def content_type(style_name=:original)
      return nil if !style_exists?(style_name)
      styles[style_name.to_s]["ct"]
    end

    def size(style_name=:original)
      return nil if !style_exists?(style_name)
      styles[style_name.to_s]["sz"]
    end

    def is_image?(style_name=:original)
      return false if content_type(style_name).nil?
      content_type(style_name).include? "image"
    end

    def is_audio?(style_name=:original)
      return false if content_type(style_name).nil?
      content_type(style_name).include? "audio"
    end

    def is_video?(style_name=:original)
      return false if !style_exists?(style_name)
      fp = styles[style_name.to_s]["path"] || styles[style_name.to_s]["cache"]
      QuickFile.is_video_file? fp
    end

    def style_exists?(style_name)
      !styles[style_name.to_s].nil?
    end

    def has_helper?(name)
      helpers[name.to_sym] != nil
    end

    def has_exif_data?(field=nil)
      has_data = !self.profile["exif"].blank?
      return has_data if field.nil?
      return false if !has_data
      return !self.profile["exif"][field].nil?
    end

    def storage_path(style_name, ext)
      # override in base class
      "#{style_name.to_s}/#{self.sanitized_basename}#{ext}"
    end

    def file_category
      return self.cat unless self.cat.nil?

      return FILE_CATEGORIES[:none] if self.state.nil?

      if self.is_image?
        return FILE_CATEGORIES[:image]
      elsif self.is_video?
        return FILE_CATEGORIES[:video]
      elsif self.is_audio?
        return FILE_CATEGORIES[:audio]
      else
        return FILE_CATEGORIES[:file]
      end
    end

    def url_hash
      ret = {}
      styles.keys.each do |style_name|
        ret[style_name] = self.url(style_name.to_sym)
      end
      ret
    end

    def processing_stats
      @processing_stats ||= {}
    end


    ## INITIALIZATION

    def source=(opts)
      if opts.is_a?(String)
        opts = JSON.parse(opts)
      end
      if opts.is_a?(Hash)
        opts = opts.symbolize_keys
        type = opts[:type].to_s
        if type == 'file'
          self.uploaded_file=(opts[:data])
        elsif type == 'url'
          self.linked_file=(opts[:data])
        elsif type == 'local'
          self.local_file=(opts[:data])
        elsif type == 'string'
          self.load_from_string(opts)
        elsif type == 'base64'
          self.load_from_base64(opts)
        else
          raise "Unknown source type."
        end
      else
        self.uploaded_file = opts
      end
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
      cache!
    end

    def local_file=(fn)
      self.error_log = []
      @local_file = fn
      self.original_filename = fn.split('/').last
      self.state! :loaded
      cache!
    end

    def load_from_string(opts)
      str = opts[:data]
      name = opts[:filename]
      self.error_log = []
      @string_file = str
      self.original_filename = name
      self.state! :loaded
      cache!
    end

    def load_from_base64(opts)
      ad = opts[:data]
      ad = ad.split(',').last if ad.include?(',')
      @binary_data = Base64.decode64(ad)
      self.error_log = []
      self.original_filename = opts[:filename]
      self.state! :loaded
      cache!
    end

    ## ACTIONS

    def cache!
      return unless state? :loaded
      add_stat(:original, :cache_start)
      cn = QuickFile.generate_cache_name(extension)
      if @uploaded_file
        cp = QuickFile.save_cache_file(cn, @uploaded_file)
      elsif @linked_url
        # download file to 
        cp = QuickFile.download_cache_file(cn, @linked_url)
      elsif @local_file
        cp = QuickFile.copy_cache_file(cn, @local_file)
      elsif @string_file
        cp = QuickFile.write_to_cache_file(cn, @string_file)
      elsif @binary_data
        cp = QuickFile.write_to_cache_file(cn, @binary_data, 'wb')
      end

      cp = before_cache(cp)

      sz = File.size(cp)
      self.styles["original"] = {
        "cache" => cp, 
        "ct" => QuickFile.content_type_for(cp),
        "sz" => sz
      }
      add_stat(:original, "cached_file_size", sz)
      add_stat(:original, "cached_file_name", self.original_filename)
      # set file category
      self.cat = QuickFile.file_category_for(cp)
      # set md5
      self.md5_hash = Digest::MD5.file(cp).hexdigest

      # handle helpers
      self.class.helpers.each do |name, helper|
        helper[:blk].call(self, cp)
      end

      self.validate!
      if self.error_log.size > 0
        self.state! :error
        File.delete(cp)
      else
        add_stat(:original, :cache_end)
        self.state! :cached
      end
    end

    def process!
      cache! if state? :loaded
      return unless state? :cached
      self.state! :processing
      self.save_if_persisted
      add_stat(:original, "all_process_start")
      begin
        #puts "#{processes.size} processes"
        processes.each do |style_name, opts|
          process_style! style_name
        end
        self.state! :processed
      rescue => e
        QuickFile.log e.message
        QuickFile.log e.backtrace.join("\n\t")
        self.error_log << "PROCESS: #{e.message}"
        self.state! :error
      end
      add_stat(:original, "all_process_end")
      self.save_if_persisted
    end

    def store!
      cache! if state? :loaded
      process! if state? :cached
      return unless state?(:processed)
      add_stat(:original, "all_store_start")
      begin
        self.styles.keys.each do |style_name|
          store_style! style_name unless styles[style_name]["cache"].nil?
        end
        self.state = STATES[:stored]
      rescue => e
        QuickFile.log e.message
        QuickFile.log e.backtrace.join("\n\t")
        self.error_log << "STORE: #{e.message}"
        if self.error_log.count < 3
          self.store!
        else
          self.state! :error
        end
      end
      add_stat(:original, "all_store_end")
      self.after_store
      self.save_if_persisted
    end

    def reprocess!(style_names)
      style_names = style_names.collect{|s| s.to_sym}
      return unless (self.state?(:stored))
      raise "Cannot reprocess original" if style_names.include?(:original)

      # download original file
      cp = QuickFile.new_cache_file File.extname(self.path(:original))
      self.storage(:original).download(self.path(:original), cp)
      self.styles["original"]["cache"] = cp

      style_names.each do |style_name|
        # delete stored style
        self.delete_style!(style_name)

        # process style
        self.process_style!(style_name)

        # store style
        self.store_style!(style_name)
      end

      # clean up original stuff
      File.delete(self.styles["original"]["cache"])
      self.styles["original"].delete("cache")

      self.save_if_persisted
    end

    def validate!
      # implement in base class to perform validations
    end

    def save_if_persisted
      if self.new_record?
        return true
      else
        return self.save
      end
    end

    def process_style!(style_name)
      add_stat(style_name, :process_start)
      style_name = style_name.to_s
      #puts "Processing #{style_name}..."
      opts = processes[style_name]
      fn = opts[:blk].call(self, styles["original"]["cache"])
      sz = styles["original"]["sz"]
      unless fn.nil?
        if (styles.key?(style_name) && !styles[style_name]["cache"].nil?)
          File.delete(styles[style_name]["cache"])
        end
        sz = File.size(fn)
        styles[style_name.to_s] = {"cache" => fn, 
                                   "ct" => QuickFile.content_type_for(fn),
                                   "sz" => sz}
      end
      add_stat(style_name, :process_end)
      add_stat(style_name, :processed_file_size, sz)
    end

    def store_style!(style_name)
      add_stat(style_name, :store_start)
      style_name = style_name.to_s
      fn = styles[style_name]["cache"]
      sz = styles[style_name]["sz"]
      sp = storage_path(style_name, File.extname(fn))
      storage = QuickFile.storage_for(:primary)
      storage.store({
        :body => File.open(fn).read,
        :content_type => QuickFile.content_type_for(fn),
        :key => sp,
      })
      styles[style_name]["path"] = sp
      styles[style_name]["ct"] = QuickFile.content_type_for(fn)
      styles[style_name]["sz"] = File.size(fn)
      styles[style_name]["stg"] = storage.name
      styles[style_name].delete("cache")

      add_stat(style_name, :store_end)
      stats = processing_stats[style_name]
      kbps = (sz / (stats["store_end"].to_f - stats["store_start"].to_f)) / 1024.0
      add_stat(style_name, :store_kbps, kbps.round(2))

      # NOTE: delete the file in 15 mins so user can access file temporarily
      `echo "rm -f #{fn}" | at now + 15 minutes`
      self.save_if_persisted
    end

    def delete_style!(style_name)
      style_name = style_name.to_s
      return if self.styles[style_name].nil?

      path = self.styles[style_name]["path"]
      cache = self.styles[style_name]["cache"]
      self.storage(style_name).delete(path) unless path.nil?
      File.delete(cache) unless cache.nil? || !File.exists?(cache)
    end

    def update_style_path!(style_name)
      style_name = style_name.to_s
      fn = self.path(style_name)
      return if fn.nil?
      np = self.storage_path(style_name, File.extname(fn))
      return if np == fn
      obj = self.storage(style_name).rename(fn, np)
      styles[style_name]["path"] = np
      self.save_if_persisted
    end

    def update_style_paths!
      return unless self.state?(:stored)
      self.styles.each do |style, data|
        self.update_style_path!(style)
      end
    end

    def download(style_name=:original, to_file=nil)
      to_file = QuickFile.new_cache_file File.extname(self.path(style_name)) if to_file.nil?
      self.storage(style_name).download(self.path(style_name), to_file)
      return to_file
    end

    def delete_files
      # delete uploaded files
      self.styles.each do |k,v|
        self.delete_style!(k)
      end
      self.state = STATES[:deleted]
      self.save_if_persisted
    end
    alias_method :delete_files!, :delete_files

    def before_cache(cp)
      return cp
    end
    def after_store

    end

    def add_stat(style, name, val = Time.now)
      st = style.to_s
      self.processing_stats[st] ||= {}
      self.processing_stats[st][name.to_s] = val
    end

    
  end

end

