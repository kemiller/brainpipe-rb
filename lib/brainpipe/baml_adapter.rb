module Brainpipe
  class BamlAdapter
    class << self
      def available?
        return @available unless @available.nil?
        @available = begin
          require "baml"
          true
        rescue LoadError
          false
        end
      end

      def require_available!
        return if available?
        raise ConfigurationError,
          "BAML is not available. Add 'baml' to your Gemfile and ensure BAML files are compiled."
      end

      def baml_client
        require_available!
        @baml_client ||= find_baml_client
      end

      def function(name)
        require_available!
        BamlFunction.new(name: name.to_sym, client: baml_client)
      end

      def to_baml_image(image)
        require_available!
        raise ConfigurationError, "Baml::Image is not available" unless defined?(::Baml::Image)

        if image.url?
          ::Baml::Image.from_url(image.url)
        else
          ::Baml::Image.from_base64(image.mime_type, image.base64)
        end
      end

      def build_client_registry(model_config)
        return nil unless model_config
        require_available!

        registry = ::Baml::ClientRegistry.new
        client = build_client_hash(model_config)
        registry.add_llm_client(model_config.name.to_s, model_config.provider.to_s, client)
        registry.set_primary(model_config.name.to_s)
        registry
      end

      def reset!
        @available = nil
        @baml_client = nil
      end

      private

      def build_client_hash(model_config)
        opts = model_config.options || {}
        client = {
          "model" => model_config.model,
          "api_key" => model_config.resolved_api_key
        }

        base_url = opts[:base_url] || opts["base_url"]
        temperature = opts[:temperature] || opts["temperature"]
        max_tokens = opts[:max_tokens] || opts["max_tokens"]
        generation_config = opts[:generation_config] || opts["generation_config"]

        client["base_url"] = base_url if base_url
        client["temperature"] = temperature if temperature
        client["max_tokens"] = max_tokens if max_tokens
        client["generationConfig"] = generation_config if generation_config
        client
      end

      def find_baml_client
        if defined?(::Baml) && ::Baml.respond_to?(:Client)
          ::Baml.Client
        elsif defined?(::B)
          ::B
        else
          raise ConfigurationError,
            "Could not find BAML client. Ensure BAML files are compiled (baml_client or B constant)."
        end
      end
    end
  end

  class BamlFunction
    attr_reader :name, :client

    def initialize(name:, client:)
      @name = name
      @client = client
      @function_info = lookup_function_info
      freeze
    end

    def call(input, client_registry: nil)
      opts = client_registry ? { baml_options: { client_registry: client_registry } } : {}
      @client.send(@name, **input, **opts)
    end

    def input_schema
      @function_info[:input_schema]
    end

    def output_schema
      @function_info[:output_schema]
    end

    private

    def lookup_function_info
      unless @client.respond_to?(@name)
        raise MissingOperationError, "BAML function '#{@name}' not found"
      end

      {
        input_schema: extract_input_schema,
        output_schema: extract_output_schema
      }
    end

    def extract_input_schema
      if defined?(::Baml::TypeBuilder) && ::Baml::TypeBuilder.respond_to?(:input_schema_for)
        convert_baml_schema(::Baml::TypeBuilder.input_schema_for(@name))
      else
        extract_input_from_method_signature
      end
    end

    def extract_output_schema
      if defined?(::Baml::TypeBuilder) && ::Baml::TypeBuilder.respond_to?(:output_schema_for)
        convert_baml_schema(::Baml::TypeBuilder.output_schema_for(@name))
      else
        {}
      end
    end

    def extract_input_from_method_signature
      method = @client.method(@name)
      schema = {}
      method.parameters.each do |type, param_name|
        next if param_name == :baml_options
        case type
        when :keyreq
          schema[param_name] = { type: Any, optional: false }
        when :key
          schema[param_name] = { type: Any, optional: true }
        end
      end
      schema
    end

    def convert_baml_schema(baml_schema)
      return {} unless baml_schema.is_a?(Hash)

      schema = {}
      baml_schema.each do |field, type_info|
        schema[field.to_sym] = {
          type: convert_baml_type(type_info),
          optional: type_info.is_a?(Hash) && type_info[:optional]
        }
      end
      schema
    end

    def convert_baml_type(type_info)
      return Any unless type_info

      case type_info
      when Class
        type_info
      when Hash
        type_info[:type] || Any
      when Symbol, String
        case type_info.to_s
        when "string" then String
        when "int", "integer" then Integer
        when "float" then Float
        when "bool", "boolean" then Boolean
        else Any
        end
      else
        Any
      end
    end
  end
end
