module Brainpipe
  module ProviderAdapters
    class OpenAI < Base
      API_URL = "https://api.openai.com/v1/chat/completions".freeze

      def call(prompt:, model_config:, images: [], json_mode: false)
        uri = URI.parse(API_URL)
        headers = build_headers(model_config)
        body = build_request_body(prompt, model_config, images, json_mode)
        execute_request(uri, body, headers)
      end

      def extract_text(response)
        response.dig("choices", 0, "message", "content")
      end

      protected

      def build_headers(model_config)
        api_key = model_config.resolved_api_key
        raise ConfigurationError, "API key required for OpenAI" unless api_key

        {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer #{api_key}"
        }
      end

      private

      def build_request_body(prompt, model_config, images, json_mode)
        content = build_content(prompt, images)

        body = {
          "model" => model_config.model,
          "messages" => [
            { "role" => "user", "content" => content }
          ]
        }

        if json_mode
          body["response_format"] = { "type" => "json_object" }
        end

        merge_options(body, model_config.options)
      end

      def build_content(prompt, images)
        return prompt if images.empty?

        content = []
        content << { "type" => "text", "text" => prompt }

        images.each do |image|
          content << {
            "type" => "image_url",
            "image_url" => {
              "url" => image_to_data_url(image)
            }
          }
        end

        content
      end

      def merge_options(body, options)
        allowed_keys = %w[temperature max_tokens top_p frequency_penalty presence_penalty]
        options.each do |key, value|
          str_key = key.to_s
          body[str_key] = value if allowed_keys.include?(str_key)
        end
        body
      end
    end
  end
end
