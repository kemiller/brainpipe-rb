module Brainpipe
  module ProviderAdapters
    class GoogleAI < Base
      API_BASE = "https://generativelanguage.googleapis.com/v1beta/models".freeze

      def call(prompt:, model_config:, images: [], json_mode: false)
        uri = build_uri(model_config)
        headers = build_headers(model_config)
        body = build_request_body(prompt, model_config, images)
        execute_request(uri, body, headers)
      end

      def extract_text(response)
        response.dig("candidates", 0, "content", "parts", 0, "text")
      end

      def extract_image(response)
        return nil unless response

        candidates = response["candidates"]
        return nil unless candidates.is_a?(Array) && !candidates.empty?

        parts = candidates.first&.dig("content", "parts")
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

      protected

      def build_headers(model_config)
        {
          "Content-Type" => "application/json"
        }
      end

      private

      def build_uri(model_config)
        api_key = model_config.resolved_api_key
        raise ConfigurationError, "API key required for Google AI" unless api_key

        URI.parse("#{API_BASE}/#{model_config.model}:generateContent?key=#{api_key}")
      end

      def build_request_body(prompt, model_config, images)
        parts = build_parts(prompt, images)

        body = {
          "contents" => [
            { "parts" => parts }
          ]
        }

        generation_config = build_generation_config(model_config.options)
        body["generationConfig"] = generation_config unless generation_config.empty?

        body
      end

      def build_parts(prompt, images)
        parts = []

        images.each do |image|
          parts << {
            "inlineData" => {
              "mimeType" => image.mime_type,
              "data" => image.base64
            }
          }
        end

        parts << { "text" => prompt }
        parts
      end

      def build_generation_config(options)
        config = {}
        mapping = {
          "temperature" => "temperature",
          "max_tokens" => "maxOutputTokens",
          "top_p" => "topP",
          "top_k" => "topK"
        }

        options.each do |key, value|
          str_key = key.to_s
          if mapping.key?(str_key)
            config[mapping[str_key]] = value
          elsif str_key == "generation_config" && value.is_a?(Hash)
            config.merge!(value)
          end
        end

        config
      end
    end
  end
end
