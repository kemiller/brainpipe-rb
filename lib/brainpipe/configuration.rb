module Brainpipe
  class Configuration
    attr_accessor :config_path, :debug, :metrics_collector, :max_threads, :thread_pool_timeout
    attr_reader :model_registry, :operation_registry, :autoload_paths

    def initialize
      @config_path = nil
      @debug = false
      @metrics_collector = nil
      @secret_resolver_proc = nil
      @max_threads = 10
      @thread_pool_timeout = 60
      @model_registry = ModelRegistry.new
      @operation_registry = {}
      @autoload_paths = []
    end

    def secret_resolver=(resolver)
      unless resolver.nil? || resolver.respond_to?(:call)
        raise ConfigurationError, "secret_resolver must respond to #call"
      end
      @secret_resolver_proc = resolver
    end

    def secret_resolver
      @secret_resolver_proc
    end

    def model(name, &block)
      builder = ModelBuilder.new(name)
      builder.instance_eval(&block)
      config = builder.build
      @model_registry.register(name, config)
    end

    def autoload_path(path)
      expanded = File.expand_path(path)
      @autoload_paths << expanded unless @autoload_paths.include?(expanded)
    end

    def register_operation(name, klass)
      key = name.to_sym
      unless klass.is_a?(Class) && klass <= Operation
        raise ConfigurationError, "Operation class must inherit from Brainpipe::Operation"
      end
      @operation_registry[key] = klass
    end

    def get_operation(name)
      @operation_registry[name.to_sym]
    end

    def load_config!
      # This is a stub - actual YAML loading will be implemented in Phase 9
      # For now, just return self to allow chaining
      self
    end

    def reset!
      @config_path = nil
      @debug = false
      @metrics_collector = nil
      @secret_resolver_proc = nil
      @max_threads = 10
      @thread_pool_timeout = 60
      @model_registry.clear!
      @operation_registry.clear
      @autoload_paths.clear
      self
    end

    def build_secret_resolver
      SecretResolver.new(secret_resolver: @secret_resolver_proc)
    end
  end

  class ModelBuilder
    def initialize(name)
      @name = name.to_sym
      @provider = nil
      @model = nil
      @capabilities = []
      @options = {}
      @api_key = nil
    end

    def provider(value)
      @provider = value.to_sym
    end

    def model(value)
      @model = value.to_s
    end

    def capabilities(*values)
      @capabilities = values.flatten.map(&:to_sym)
    end

    def options(hash)
      @options = hash
    end

    def api_key(value)
      @api_key = value
    end

    def build
      raise ConfigurationError, "Model '#{@name}' requires a provider" unless @provider
      raise ConfigurationError, "Model '#{@name}' requires a model name" unless @model
      raise ConfigurationError, "Model '#{@name}' requires at least one capability" if @capabilities.empty?

      opts = @options.dup
      opts[:api_key] = @api_key if @api_key

      ModelConfig.new(
        name: @name,
        provider: @provider,
        model: @model,
        capabilities: @capabilities,
        options: opts
      )
    end
  end
end
