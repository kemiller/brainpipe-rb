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
      registry.add_llm_client(name: @name.to_s, provider: @provider.to_s, options: client)
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
      api_key = @options[:api_key]
      return nil unless api_key
      SecretResolver.new.resolve(api_key)
    end

    def baml_options
      opts = {}
      opts["base_url"] = @options[:base_url] if @options[:base_url]
      opts["temperature"] = @options[:temperature] if @options[:temperature]
      opts["max_tokens"] = @options[:max_tokens] if @options[:max_tokens]
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
