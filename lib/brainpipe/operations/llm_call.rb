require "mustache"

module Brainpipe
  module Operations
    class LlmCall < Operation
      def initialize(model: nil, options: {})
        @capability = (options[:capability] || :text_to_text).to_sym
        @inputs = normalize_type_hash(options[:inputs] || {})
        @outputs = normalize_type_hash(options[:outputs] || {})
        @template = load_template(options)
        @json_mode = options.key?(:json_mode) ? options[:json_mode] : default_json_mode

        validate_capability!
        validate_inputs!
        validate_outputs!
        validate_model_capability!(model) if model

        super
      end

      def required_model_capability
        @capability
      end

      def declared_reads(prefix_schema = {})
        @inputs.transform_values do |type_info|
          { type: type_info[:type], optional: type_info[:optional] || false }
        end
      end

      def declared_sets(prefix_schema = {})
        @outputs.transform_values do |type_info|
          { type: type_info[:type], optional: type_info[:optional] || false }
        end
      end

      def declared_deletes(prefix_schema = {})
        []
      end

      def create
        template = @template
        inputs = @inputs
        outputs = @outputs
        model_config = @model
        json_mode = @json_mode

        ->(namespaces) do
          namespaces.map do |ns|
            adapter = ProviderAdapters.for(model_config.provider)

            context, images = build_context_and_images(ns, inputs)
            prompt = Mustache.render(template, context)

            response = adapter.call(
              prompt: prompt,
              model_config: model_config,
              images: images,
              json_mode: json_mode
            )

            output = extract_output(response, adapter, outputs)
            ns.merge(output)
          end
        end
      end

      private

      def load_template(options)
        if options[:prompt]
          options[:prompt]
        elsif options[:prompt_file]
          load_template_file(options[:prompt_file])
        else
          raise ConfigurationError, "LlmCall operation requires 'prompt' or 'prompt_file' option"
        end
      end

      def load_template_file(path)
        config_path = Brainpipe.configuration&.config_path
        full_path = if config_path
          File.expand_path(path, File.dirname(config_path))
        else
          File.expand_path(path)
        end

        unless File.exist?(full_path)
          raise ConfigurationError, "Prompt file not found: #{full_path}"
        end

        File.read(full_path)
      end

      def normalize_type_hash(hash)
        hash.transform_keys(&:to_sym).transform_values do |value|
          case value
          when Hash
            { type: resolve_type(value[:type] || value["type"]), optional: value[:optional] || value["optional"] || false }
          when String, Symbol
            { type: resolve_type(value), optional: false }
          when Class
            { type: value, optional: false }
          else
            { type: Any, optional: false }
          end
        end
      end

      def resolve_type(type_value)
        return Any if type_value.nil?
        return type_value if type_value.is_a?(Class)

        type_str = type_value.to_s
        case type_str.downcase
        when "string" then String
        when "integer" then Integer
        when "float" then Float
        when "boolean" then Boolean
        when "image" then Image
        when "array" then Array
        when "hash" then Hash
        else Any
        end
      end

      def validate_capability!
        unless Capabilities.valid?(@capability)
          raise ConfigurationError, "Invalid capability: '#{@capability}'. Valid: #{Capabilities::VALID_CAPABILITIES.join(', ')}"
        end
      end

      def validate_inputs!
        if @inputs.empty?
          raise ConfigurationError, "LlmCall operation requires at least one input"
        end
      end

      def validate_outputs!
        if @outputs.empty?
          raise ConfigurationError, "LlmCall operation requires at least one output"
        end
      end

      def validate_model_capability!(model)
        unless model.has_capability?(@capability)
          raise CapabilityMismatchError,
            "LlmCall operation requires '#{@capability}' capability, " \
            "but model '#{model.name}' only has: #{model.capabilities.join(', ')}"
        end
      end

      def default_json_mode
        @outputs.values.none? { |v| v[:type] == Image }
      end

      def build_context_and_images(namespace, inputs)
        context = {}
        images = []

        inputs.each do |field, type_info|
          value = namespace[field]
          if type_info[:type] == Image || value.is_a?(Image)
            context[field] = "[IMAGE]"
            images << value if value
          else
            context[field] = value
          end
        end

        [context, images]
      end

      def extract_output(response, adapter, outputs)
        has_image_output = outputs.values.any? { |v| v[:type] == Image }

        if has_image_output
          extract_image_output(response, adapter, outputs)
        else
          extract_text_output(response, adapter, outputs)
        end
      end

      def extract_image_output(response, adapter, outputs)
        image = adapter.extract_image(response)

        raise ExecutionError, "No image found in response" unless image

        output = {}
        outputs.each do |field, type_info|
          if type_info[:type] == Image
            output[field] = image
          end
        end
        output
      end

      def extract_text_output(response, adapter, outputs)
        text = adapter.extract_text(response)
        raise ExecutionError, "No text found in response" unless text

        begin
          parsed = JSON.parse(text)
        rescue JSON::ParserError => e
          raise ExecutionError, "Failed to parse JSON response: #{e.message}\nResponse: #{text}"
        end

        output = {}
        outputs.each do |field, type_info|
          str_field = field.to_s
          value = parsed[str_field] || parsed[field]

          if value.nil? && !type_info[:optional]
            raise ExecutionError, "Missing required output field '#{field}' in response"
          end

          output[field] = value unless value.nil?
        end
        output
      end
    end
  end
end
