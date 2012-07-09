require "quick_file/version"
require "quick_file/upload"
require "mime/types"
require "fog"
require "RMagick"

module QuickFile
  CACHE_DIR = "/tmp"

  class << self
    def configure
      yield options if block_given?
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

    def fog_connection
      @@fog_connection ||= begin
        Fog::Storage.new(options[:fog_credentials])
      end
    end

    def fog_directory
      @@fog_directory ||= begin
          fog_connection.directories.new(
          :key => options[:fog_directory],
          :public => options[:fog_public]
        )
      end
    end

    def host_url
      @@host_url ||= begin
        {
          :s3 => "s3.amazonaws.com/#{options[:fog_directory]}/"
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
      out = open(to, "wb")
      out.write(open(url).read)
      out.close
    end

    def image_from_url(url)
      open(url, 'rb') do |f|
        image = Magick::Image.from_blob(f.read).first
      end
      image
    end


  end

end
