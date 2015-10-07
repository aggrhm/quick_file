require "active_support/all"
require "mime/types"
require "rmagick"
require "find"
require "quick_file/version"
require "quick_file/storage"
require "quick_file/storage/s3_storage"
require "quick_file/storage/swift_storage"
require "quick_file/storage/local_storage"
require "quick_file/upload"

module QuickFile
  CACHE_DIR = "/tmp"
  STORAGE_TYPES = {:local => 1, :aws => 2, :ceph => 3}
  FILE_CATEGORIES = {:none => 0, :image => 1, :video => 2, :audio => 3}

  if defined?(Rails)
    # load configuration
    class Railtie < Rails::Railtie
      initializer "quick_file.configure" do
        QuickFile.logger = Rails.logger
        config_file = Rails.root.join("config", "quick_file.yml")
        QuickFile.configure(YAML.load_file(config_file)[Rails.env]) unless config_file.nil?
        # clean cache dir if development
        if Rails.env.to_sym == :development
          QuickFile.clean_cache_directory
        end
      end
    end
  end

  class << self
    def configure(opt=nil)
      if block_given?
        yield options
      else
        # handle hash
        options.merge! opt.recursive_symbolize_keys!
      end
    end

    def options
      @@options ||= {}
    end

    def logger=(logger)
      @logger = logger
    end
    def logger
      @logger
    end
    def log(msg, level=Logger::INFO)
      if @logger
        @logger.add(level, msg)
      else
        puts msg
      end
    end

    def generate_cache_name(ext)
      "#{SecureRandom.hex(5)}#{ext}"
    end

    def new_cache_file(ext)
      QuickFile.cache_path QuickFile.generate_cache_name(ext)
    end

    def content_type_for(filename)
      mime = MIME::Types.type_for(filename)[0]
      return mime.simplified if mime
      return "application/file"
    end

    def is_video_file?(filename)
      filename.downcase.end_with?('.mov', '.3gp', '.wmv', '.m4v', '.mp4', '.flv')
    end
		def is_image_file?(filename)
      ct = content_type_for(filename)
			return false if ct.nil?
			ct.include? "image"
		end
		def is_audio_file?(filename)
      ct = content_type_for(filename)
			return false if ct.nil?
			ct.include? "audio"
		end


    def file_category_for(filename)
      ct = content_type_for(filename)
      if ct.include? "image"
        return FILE_CATEGORIES[:image]
      elsif ct.include? "audio"
        return FILE_CATEGORIES[:audio]
      elsif is_video_file?(filename)
        return FILE_CATEGORIES[:video]
      else
        return FILE_CATEGORIES[:none]
      end
    end

    def storage_map
      @@storage_map ||= begin
        ret = {}
        options[:connections].each do |conn|
          ret[conn[:name]] = QuickFile::Storage.build_for_connection(conn)
        end
        ret[:cache] = ret["cache"] = QuickFile::Storage.build_for_connection({provider: :local, local_root: "/tmp", directory: "uploads"}.merge(options[:cache]))
        ret
      end
    end

    def storage_for(name)
      if name.blank?
        return self.storage_map.values.select{|s| s.default_when_blank?}.first || self.storage_for(:primary)
      elsif name == :primary
        return self.storage_map.values.select{|s| s.primary?}.first || self.storage_map.values.first
      else
        return self.storage_map[name]
      end
    end

    def resize_to_fit(file, x, y)
      img = Magick::Image.read(file).first
      nim = img.resize_to_fit x, y
      outfile = cache_path(generate_cache_name(File.extname(file)))
      nim.write outfile
      outfile
    end

    def resize_to_fill(file, x, y)
      img = Magick::Image.read(file).first
      nim = img.resize_to_fill(x, y)
      outfile = cache_path(generate_cache_name(File.extname(file)))
      nim.write outfile
      outfile
    end

    def auto_orient!(file)
      `/usr/bin/mogrify -auto-orient #{file}`
      return file
    end

    def extract_image_data(file)
      img = Magick::Image.read(file).first
      ret = {}
      ret['width'] = img.columns
      ret['height'] = img.rows
      ret['format'] = img.format
      ret['depth'] = img.depth
      ret['resolution_x'] = img.x_resolution
      ret['resolution_y'] = img.y_resolution
      return ret
    end

    def extract_exif_data(file)
      img = Magick::Image.read(file).first
      data = img.get_exif_by_entry
      ret = {}
      data.each do |el|
        ret[el[0]] = el[1]
      end
      return ret
    end

    def parse_exif_time(str)
      ds,ts = str.split(' ')
      year,month,day = ds.split(':')
      hour,min,sec = ts.split(':')
      Time.utc(year, month, day, hour, min, sec)
    end

		def convert_video_to_mp4(file)
      new_file = QuickFile.new_cache_file(".mp4")
      `ffmpeg -i #{file} -vcodec libx264 -b 500k -bt 50k -acodec libfaac -ab 56k -ac 2 -s 480x320 #{new_file}`
			new_file
		end

		def convert_video_to_flv(file)
      new_file = QuickFile.new_cache_file(".flv")
      `ffmpeg -i #{file} -f flv -ar 11025 -r 24 -s 480x320 #{new_file}`
			new_file
		end

		def create_video_thumb(file)
      new_file = QuickFile.new_cache_file(".jpg")
      `ffmpeg -i #{file} #{new_file}`
			new_file
		end

    def cache_directory
      cp = File.join(options[:cache][:local_root], options[:cache][:directory])
      FileUtils.mkdir_p(cp) if !File.directory?(cp)
      return cp
    end

    def cache_path(cn=nil)
      cp = File.join(cache_directory, cn)
      return cp
    end

    def download(url, to)
      File.open(to, "wb") do |saved_file|
        open(url, "rb") do |read_file|
          saved_file.write(read_file.read)
        end
      end
    end

    def image_from_url(url)
      open(url, 'rb') do |f|
        image = Magick::Image.from_blob(f.read).first
      end
      image
    end

    def save_cache_file(cn, file)
      cp = QuickFile.cache_path(cn)
      File.open(cp, "wb") { |f| f.write(file.read) }
      return cp
    end

    def copy_cache_file(cn, fn)
      cp = QuickFile.cache_path(cn)
      FileUtils.copy(fn, cp)
      return cp
    end

    def download_cache_file(cn, url)
      cp = QuickFile.cache_path(cn)
      QuickFile.download(url, cp)
      return cp
    end

    def write_to_cache_file(cn, str, wf="w")
      cp = QuickFile.cache_path(cn)
      File.open(cp, wf) { |f| f.write(str) }
      return cp
    end

    def clean_cache_directory(opts={})
      #opts[:max_age] ||= 3600*24
      opts[:max_age] ||= 10
      QuickFile.log "Cleaning cache directory..."
      # delete any files older than a day
      Find.find(cache_directory) do |file|
        if File.file?(file) && (Time.now - File.stat(file).mtime) > opts[:max_age]
          QuickFile.log "Deleting cached file #{file}."
          File.delete(file)
        end
      end
      QuickFile.log "Cache cleaning done."
    end

  end

end

class Hash
  def recursive_symbolize_keys!
    symbolize_keys!
    # symbolize each hash in .values
    values.each{|h| h.recursive_symbolize_keys! if h.is_a?(Hash) }
    # symbolize each hash inside an array in .values
    values.select{|v| v.is_a?(Array) }.flatten.each{|h| h.recursive_symbolize_keys! if h.is_a?(Hash) }
    self
  end
end

