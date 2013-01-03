require "quick_file/version"
require "quick_file/storage"
require "quick_file/upload"
require "mime/types"
require "RMagick"

module QuickFile
  CACHE_DIR = "/tmp"
  STORAGE_TYPES = {:local => 1, :aws => 2, :ceph => 3}

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

    def storage
      @@storage ||= begin
        storage = QuickFile::Storage.new(options[:connection])
        storage.set_bucket(options[:directory])
        storage
      end
    end

    def fog_directory
      @@fog_directory ||= begin
          fog_connection.directories.new(
          :key => options[:fog][:directory],
          :public => options[:fog][:public]
        )
      end
    end

    def host_url
      @@host_url ||= begin
        {
          1 => "#{options[:fog][:connection][:local_root]}/#{options[:fog][:directory]}/",
          2 => "https://s3.amazonaws.com/#{options[:fog][:directory]}/"
        }
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

    def cache_path(cn)
      File.join(CACHE_DIR, cn)
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

