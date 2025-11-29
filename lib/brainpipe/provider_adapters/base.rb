require "net/http"
require "uri"
require "json"

module Brainpipe
  module ProviderAdapters
    class Base
      def call(prompt:, model_config:, images: [], json_mode: false)
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end

      def extract_text(response)
        raise NotImplementedError, "#{self.class}#extract_text must be implemented"
      end

      def extract_image(response)
        nil
      end

      protected

      def build_headers(model_config)
        raise NotImplementedError, "#{self.class}#build_headers must be implemented"
      end

      def execute_request(uri, body, headers, timeout: 120)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = timeout
        http.open_timeout = timeout

        request = Net::HTTP::Post.new(uri.request_uri)
        headers.each { |key, value| request[key] = value }
        request.body = body.is_a?(String) ? body : JSON.generate(body)

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise ExecutionError, "HTTP request failed: #{response.code} #{response.message} - #{response.body}"
        end

        JSON.parse(response.body)
      end

      def image_to_data_url(image)
        "data:#{image.mime_type};base64,#{image.base64}"
      end
    end
  end
end
