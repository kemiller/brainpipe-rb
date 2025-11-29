require "net/http"
require "uri"
require "base64"

module Brainpipe
  class Image
    MIME_TYPES = {
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".png" => "image/png",
      ".gif" => "image/gif",
      ".webp" => "image/webp",
      ".bmp" => "image/bmp",
      ".svg" => "image/svg+xml"
    }.freeze

    attr_reader :mime_type

    def initialize(url: nil, base64: nil, mime_type: nil)
      raise ArgumentError, "Must provide either url or base64" if url.nil? && base64.nil?
      raise ArgumentError, "Cannot provide both url and base64" if url && base64

      @url = url
      @base64_data = base64
      @mime_type = mime_type
      @cache = [] # mutable container for lazy-loaded data
      @mutex = Mutex.new
      freeze
    end

    def self.from_url(url, mime_type: nil)
      inferred_mime = mime_type || infer_mime_type_from_url(url)
      new(url: url, mime_type: inferred_mime)
    end

    def self.from_base64(data, mime_type:)
      raise ArgumentError, "mime_type is required for base64 images" if mime_type.nil?
      new(base64: data, mime_type: mime_type)
    end

    def self.from_file(path)
      raise ArgumentError, "File not found: #{path}" unless File.exist?(path)

      data = Base64.strict_encode64(File.binread(path))
      mime = infer_mime_type_from_path(path)
      raise ArgumentError, "Could not determine MIME type for: #{path}" unless mime

      new(base64: data, mime_type: mime)
    end

    def url?
      !@url.nil?
    end

    def base64?
      !@base64_data.nil?
    end

    def url
      raise ArgumentError, "This image was created from base64 data and has no URL" unless url?
      @url
    end

    def base64
      return @base64_data if @base64_data

      @mutex.synchronize do
        return @cache[0] if @cache[0]
        @cache[0] = fetch_and_encode_url
      end
      @cache[0]
    end

    def inspect
      if url?
        "#<Brainpipe::Image url=#{@url.inspect} mime_type=#{@mime_type.inspect}>"
      else
        "#<Brainpipe::Image base64=[#{@base64_data&.length || 0} bytes] mime_type=#{@mime_type.inspect}>"
      end
    end

    def self.infer_mime_type_from_url(url)
      uri = URI.parse(url)
      infer_mime_type_from_path(uri.path)
    rescue URI::InvalidURIError
      nil
    end

    def self.infer_mime_type_from_path(path)
      ext = File.extname(path).downcase
      MIME_TYPES[ext]
    end

    private

    def fetch_and_encode_url
      uri = URI.parse(@url)
      response = Net::HTTP.get_response(uri)

      case response
      when Net::HTTPSuccess
        Base64.strict_encode64(response.body)
      when Net::HTTPRedirection
        redirected_url = response["location"]
        uri = URI.parse(redirected_url)
        response = Net::HTTP.get_response(uri)
        raise ExecutionError, "Failed to fetch image from #{@url}: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
        Base64.strict_encode64(response.body)
      else
        raise ExecutionError, "Failed to fetch image from #{@url}: #{response.code}"
      end
    end
  end
end
