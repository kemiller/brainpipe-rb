module Brainpipe
  class ModelConfig
    attr_reader :name, :provider, :model, :capabilities, :options

    def initialize(name:, provider:, model:, capabilities:, options: {})
      @name = name.to_sym
      @provider = provider.to_sym
      @model = model.to_s.freeze
      @capabilities = Array(capabilities).map(&:to_sym).freeze
      @options = options.freeze

      validate_capabilities!
      freeze
    end

    def has_capability?(capability)
      @capabilities.include?(capability.to_sym)
    end

    def to_baml_client_registry
      return nil unless BamlAdapter.available?

      require "baml"
      registry = ::Baml::ClientRegistry.new

      client = build_baml_client
      registry.add_llm_client(@name.to_s, @provider.to_s, client)
      registry.set_primary(@name.to_s)

      registry
    end

    def build_baml_client
      {
        "model" => @model,
        "api_key" => resolved_api_key
      }.merge(baml_options)
    end

    def resolved_api_key
      api_key = @options[:api_key] || @options["api_key"]
      return nil unless api_key
      SecretResolver.new.resolve(api_key)
    end

    def baml_options
      opts = {}
      base_url = @options[:base_url] || @options["base_url"]
      temperature = @options[:temperature] || @options["temperature"]
      max_tokens = @options[:max_tokens] || @options["max_tokens"]
      generation_config = @options[:generation_config] || @options["generation_config"]
      opts["base_url"] = base_url if base_url
      opts["temperature"] = temperature if temperature
      opts["max_tokens"] = max_tokens if max_tokens
      opts["generationConfig"] = generation_config if generation_config
      opts
    end

    private

    def validate_capabilities!
      invalid = @capabilities.reject { |c| Capabilities.valid?(c) }
      return if invalid.empty?

      raise ConfigurationError,
        "Invalid capabilities for model '#{@name}': #{invalid.join(', ')}. " \
        "Valid capabilities: #{Capabilities::VALID_CAPABILITIES.join(', ')}"
    end
  end
end
