module Brainpipe
  class ModelRegistry
    def initialize
      @models = {}
    end

    def register(name, config)
      key = name.to_sym
      unless config.is_a?(ModelConfig)
        raise ArgumentError, "Expected ModelConfig, got #{config.class}"
      end
      @models[key] = config
    end

    def get(name)
      key = name.to_sym
      @models.fetch(key) do
        raise MissingModelError, "Model '#{name}' not found"
      end
    end

    def get?(name)
      @models[name.to_sym]
    end

    def clear!
      @models.clear
    end

    def names
      @models.keys
    end

    def size
      @models.size
    end
  end
end
