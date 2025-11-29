module Brainpipe
  module ProviderAdapters
    class Anthropic < Base
      API_URL = "https://api.anthropic.com/v1/messages".freeze
      API_VERSION = "2023-06-01".freeze

      def call(prompt:, model_config:, images: [], json_mode: false)
        uri = URI.parse(API_URL)
        headers = build_headers(model_config)
        body = build_request_body(prompt, model_config, images)
        execute_request(uri, body, headers)
      end

      def extract_text(response)
        response.dig("content", 0, "text")
      end

      protected

      def build_headers(model_config)
        api_key = model_config.resolved_api_key
        raise ConfigurationError, "API key required for Anthropic" unless api_key

        {
          "Content-Type" => "application/json",
          "x-api-key" => api_key,
          "anthropic-version" => API_VERSION
        }
      end

      private

      def build_request_body(prompt, model_config, images)
        content = build_content(prompt, images)
        max_tokens = model_config.options[:max_tokens] || model_config.options["max_tokens"] || 4096

        body = {
          "model" => model_config.model,
          "max_tokens" => max_tokens,
          "messages" => [
            { "role" => "user", "content" => content }
          ]
        }

        merge_options(body, model_config.options)
      end

      def build_content(prompt, images)
        return prompt if images.empty?

        content = []

        images.each do |image|
          content << {
            "type" => "image",
            "source" => {
              "type" => "base64",
              "media_type" => image.mime_type,
              "data" => image.base64
            }
          }
        end

        content << { "type" => "text", "text" => prompt }
        content
      end

      def merge_options(body, options)
        allowed_keys = %w[temperature top_p top_k]
        options.each do |key, value|
          str_key = key.to_s
          body[str_key] = value if allowed_keys.include?(str_key)
        end
        body
      end
    end
  end
end
