require_relative "brainpipe/version"
require_relative "brainpipe/errors"
require_relative "brainpipe/namespace"
require_relative "brainpipe/types"
require_relative "brainpipe/type_checker"

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
      @models ||= {}
      @models[name.to_sym] or raise MissingModelError, "Model '#{name}' not found"
    end

    def reset!
      @configuration = nil
      @loaded = false
      @pipes = {}
      @models = {}
      self
    end

    def loaded?
      @loaded == true
    end
  end

  class Configuration
    attr_accessor :config_path, :debug

    def initialize
      @config_path = nil
      @debug = false
    end
  end
end
