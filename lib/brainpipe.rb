require_relative "brainpipe/version"
require_relative "brainpipe/errors"
require_relative "brainpipe/namespace"
require_relative "brainpipe/types"
require_relative "brainpipe/type_checker"
require_relative "brainpipe/capabilities"
require_relative "brainpipe/secret_resolver"
require_relative "brainpipe/model_config"
require_relative "brainpipe/model_registry"
require_relative "brainpipe/operation"
require_relative "brainpipe/operations/transform"
require_relative "brainpipe/operations/filter"
require_relative "brainpipe/operations/merge"
require_relative "brainpipe/operations/log"
require_relative "brainpipe/observability/metrics_collector"
require_relative "brainpipe/observability/debug"
require_relative "brainpipe/executor"
require_relative "brainpipe/stage"
require_relative "brainpipe/pipe"
require_relative "brainpipe/configuration"
require_relative "brainpipe/loader"

module Brainpipe
  class << self
    attr_reader :configuration

    def configure
      @configuration ||= Configuration.new
      yield(@configuration) if block_given?
      @configuration
    end

    def load!
      raise ConfigurationError, "Brainpipe.configure must be called before Brainpipe.load!" unless @configuration
      loader = Loader.new(@configuration)
      loader.load!
      @pipes = loader.load_pipes
      @loaded = true
      self
    end

    def pipe(name)
      raise ConfigurationError, "Brainpipe.load! must be called before accessing pipes" unless @loaded
      @pipes ||= {}
      @pipes[name.to_sym] or raise MissingPipeError, "Pipe '#{name}' not found"
    end

    def model(name)
      raise ConfigurationError, "Brainpipe.load! must be called before accessing models" unless @loaded
      @configuration.model_registry.get(name)
    end

    def reset!
      @configuration&.reset!
      @configuration = nil
      @loaded = false
      @pipes = {}
      self
    end

    def loaded?
      @loaded == true
    end
  end
end
