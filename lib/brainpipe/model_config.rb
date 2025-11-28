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
      raise NotImplementedError, "BAML integration not yet implemented"
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
