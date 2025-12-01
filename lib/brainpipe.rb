require_relative "brainpipe/version"
require_relative "brainpipe/errors"
require_relative "brainpipe/namespace"
require_relative "brainpipe/image"
require_relative "brainpipe/types"
require_relative "brainpipe/type_checker"
require_relative "brainpipe/capabilities"
require_relative "brainpipe/secret_resolver"
require_relative "brainpipe/model_config"
require_relative "brainpipe/model_registry"
require_relative "brainpipe/provider_adapters"
require_relative "brainpipe/operation"
require_relative "brainpipe/operations/transform"
require_relative "brainpipe/operations/filter"
require_relative "brainpipe/operations/merge"
require_relative "brainpipe/operations/log"
require_relative "brainpipe/operations/link"
require_relative "brainpipe/operations/collapse"
require_relative "brainpipe/operations/explode"
require_relative "brainpipe/baml_adapter"
require_relative "brainpipe/operations/baml"
require_relative "brainpipe/operations/baml_raw"
require_relative "brainpipe/operations/llm_call"
require_relative "brainpipe/observability/metrics_collector"
require_relative "brainpipe/observability/debug"
require_relative "brainpipe/executor"
require_relative "brainpipe/stage"
require_relative "brainpipe/pipe"
require_relative "brainpipe/configuration"
require_relative "brainpipe/loader"

# Brainpipe is a Ruby gem for building type-safe, observable LLM pipelines.
#
# @example Basic usage
#   Brainpipe.configure do |config|
#     config.model :gpt4 do
#       provider :openai
#       model "gpt-4"
#       capabilities :text_to_text
#     end
#   end
#   Brainpipe.load!
#   result = Brainpipe.pipe(:my_pipeline).call(input: "data")
#
module Brainpipe
  class << self
    # @return [Configuration, nil] the current configuration
    attr_reader :configuration

    # Configure Brainpipe with models, operations, and settings.
    # @yield [Configuration] the configuration object
    # @return [Configuration]
    def configure
      @configuration ||= Configuration.new
      yield(@configuration) if block_given?
      @configuration
    end

    # Load configuration and pipes from the configured path.
    # @raise [ConfigurationError] if configure was not called first
    # @return [Brainpipe]
    def load!
      raise ConfigurationError, "Brainpipe.configure must be called before Brainpipe.load!" unless @configuration
      loader = Loader.new(@configuration)
      loader.load!
      @pipes = loader.load_pipes
      @loaded = true
      self
    end

    # Get a named pipe.
    # @param name [Symbol, String] the pipe name
    # @raise [ConfigurationError] if load! was not called
    # @raise [MissingPipeError] if the pipe does not exist
    # @return [Pipe]
    def pipe(name)
      raise ConfigurationError, "Brainpipe.load! must be called before accessing pipes" unless @loaded
      @pipes ||= {}
      @pipes[name.to_sym] or raise MissingPipeError, "Pipe '#{name}' not found"
    end

    # Get a named model configuration.
    # @param name [Symbol, String] the model name
    # @raise [ConfigurationError] if load! was not called
    # @raise [MissingModelError] if the model does not exist
    # @return [ModelConfig]
    def model(name)
      raise ConfigurationError, "Brainpipe.load! must be called before accessing models" unless @loaded
      @configuration.model_registry.get(name)
    end

    # Reset all configuration and loaded state.
    # @return [Brainpipe]
    def reset!
      @configuration&.reset!
      @configuration = nil
      @loaded = false
      @pipes = {}
      self
    end

    # Check if Brainpipe has been loaded.
    # @return [Boolean]
    def loaded?
      @loaded == true
    end
  end
end
