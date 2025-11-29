module Brainpipe
  module Extractors
    module GeminiImage
      def self.call(response)
        return nil if response.nil? || response.empty?

        candidates = response["candidates"]
        return nil unless candidates.is_a?(Array) && !candidates.empty?

        content = candidates.first&.dig("content")
        return nil unless content

        parts = content["parts"]
        return nil unless parts.is_a?(Array)

        parts.each do |part|
          inline_data = part["inlineData"]
          next unless inline_data

          mime_type = inline_data["mimeType"]
          data = inline_data["data"]
          next unless mime_type && data

          return Image.from_base64(data, mime_type: mime_type)
        end

        nil
      end
    end
  end
end
