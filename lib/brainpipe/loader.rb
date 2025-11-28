require "yaml"
require "zeitwerk"

module Brainpipe
  class Loader
    attr_reader :configuration

    def initialize(configuration)
      @configuration = configuration
      @zeitwerk_loader = nil
    end

    def load!
      setup_zeitwerk(configuration.autoload_paths)
      load_config_file if configuration.config_path
      load_pipes
    end

    def setup_zeitwerk(paths)
      return if paths.empty? && default_autoload_paths.empty?

      @zeitwerk_loader = Zeitwerk::Loader.new
      @zeitwerk_loader.tag = "brainpipe"

      all_paths = (default_autoload_paths + paths).uniq
      all_paths.each do |path|
        @zeitwerk_loader.push_dir(path) if File.directory?(path)
      end

      @zeitwerk_loader.setup
    end

    def load_config_file
      path = resolve_config_path
      return unless path && File.exist?(path)

      yaml = parse_yaml_file(path)
      return unless yaml

      apply_config(yaml)
    end

    def load_pipes
      pipes_path = resolve_pipes_path
      return {} unless pipes_path && File.directory?(pipes_path)

      Dir.glob(File.join(pipes_path, "*.yml")).each_with_object({}) do |file, pipes|
        pipe = load_pipe_file(file)
        pipes[pipe.name] = pipe if pipe
      end
    end

    def load_pipe_file(path)
      yaml = parse_yaml_file(path)
      return nil unless yaml

      build_pipe(yaml)
    end

    def resolve_operation(type_string)
      return configuration.get_operation(type_string) if configuration.get_operation(type_string)

      klass = resolve_class(type_string)

      unless klass
        raise MissingOperationError, "Operation '#{type_string}' not found. " \
          "Ensure it's defined in autoload paths or registered via register_operation"
      end

      unless klass <= Operation
        raise ConfigurationError, "#{type_string} must inherit from Brainpipe::Operation"
      end

      klass
    end

    def build_pipe(yaml_hash)
      name = yaml_hash["name"] || yaml_hash[:name]
      raise InvalidYAMLError, "Pipe definition missing 'name'" unless name

      stages_yaml = yaml_hash["stages"] || yaml_hash[:stages] || []
      raise InvalidYAMLError, "Pipe '#{name}' missing 'stages'" if stages_yaml.empty?

      timeout = yaml_hash["timeout"] || yaml_hash[:timeout]
      stages = stages_yaml.map { |stage_yaml| build_stage(stage_yaml) }

      Pipe.new(
        name: name,
        stages: stages,
        timeout: timeout,
        debug: configuration.debug
      )
    end

    def build_stage(yaml_hash)
      name = yaml_hash["name"] || yaml_hash[:name]
      raise InvalidYAMLError, "Stage definition missing 'name'" unless name

      mode = yaml_hash["mode"] || yaml_hash[:mode] || "merge"
      merge_strategy = yaml_hash["merge_strategy"] || yaml_hash[:merge_strategy] || "last_in"
      timeout = yaml_hash["timeout"] || yaml_hash[:timeout]
      ops_yaml = yaml_hash["operations"] || yaml_hash[:operations] || []

      operations = ops_yaml.map { |op_yaml| build_operation(op_yaml) }

      Stage.new(
        name: name,
        mode: mode.to_sym,
        operations: operations,
        merge_strategy: merge_strategy.to_sym,
        timeout: timeout,
        debug: configuration.debug
      )
    end

    private

    def default_autoload_paths
      paths = []
      paths << File.expand_path("app/operations", Dir.pwd)
      paths << File.expand_path("lib/operations", Dir.pwd)
      paths
    end

    def resolve_config_path
      return nil unless configuration.config_path

      path = File.expand_path(configuration.config_path)
      config_file = File.join(path, "config.yml")
      File.exist?(config_file) ? config_file : nil
    end

    def resolve_pipes_path
      return nil unless configuration.config_path

      path = File.expand_path(configuration.config_path)
      pipes_dir = File.join(path, "pipes")
      File.directory?(pipes_dir) ? pipes_dir : nil
    end

    def parse_yaml_file(path)
      content = File.read(path)
      YAML.safe_load(content, permitted_classes: [Symbol], symbolize_names: false)
    rescue Psych::SyntaxError => e
      raise InvalidYAMLError, "Invalid YAML in #{path}: #{e.message}"
    rescue Errno::ENOENT
      raise InvalidYAMLError, "File not found: #{path}"
    end

    def apply_config(yaml)
      apply_debug(yaml)
      apply_models(yaml)
    end

    def apply_debug(yaml)
      debug_value = yaml["debug"] || yaml[:debug]
      configuration.debug = debug_value unless debug_value.nil?
    end

    def apply_models(yaml)
      models = yaml["models"] || yaml[:models]
      return unless models

      secret_resolver = configuration.build_secret_resolver

      models.each do |name, config|
        provider = config["provider"] || config[:provider]
        model = config["model"] || config[:model]
        capabilities = config["capabilities"] || config[:capabilities] || []
        options = config["options"] || config[:options] || {}

        resolved_options = resolve_options(options, secret_resolver)

        model_config = ModelConfig.new(
          name: name,
          provider: provider,
          model: model,
          capabilities: capabilities,
          options: resolved_options
        )

        configuration.model_registry.register(name.to_sym, model_config)
      end
    end

    def resolve_options(options, secret_resolver)
      options.transform_values do |value|
        if value.is_a?(String)
          secret_resolver.resolve(value)
        elsif value.is_a?(Hash)
          resolve_options(value, secret_resolver)
        else
          value
        end
      end
    end

    def build_operation(yaml_hash)
      type_string = yaml_hash["type"] || yaml_hash[:type]
      raise InvalidYAMLError, "Operation definition missing 'type'" unless type_string

      klass = resolve_operation(type_string)

      model_name = yaml_hash["model"] || yaml_hash[:model]
      options = yaml_hash["options"] || yaml_hash[:options] || {}
      timeout = yaml_hash["timeout"] || yaml_hash[:timeout]

      options = options.transform_keys(&:to_sym)
      options[:timeout] = timeout if timeout

      model = resolve_model(model_name, klass)
      validate_model_capability!(klass, model, model_name)

      klass.new(model: model, options: options)
    end

    def resolve_model(model_name, operation_class)
      return nil unless model_name

      configuration.model_registry.get(model_name.to_sym)
    end

    def validate_model_capability!(operation_class, model, model_name)
      required_capability = operation_class._required_model_capability
      return unless required_capability

      unless model
        raise CapabilityMismatchError,
          "Operation #{operation_class.name} requires a model with '#{required_capability}' capability, " \
          "but no model was specified"
      end

      unless model.has_capability?(required_capability)
        raise CapabilityMismatchError,
          "Operation #{operation_class.name} requires '#{required_capability}' capability, " \
          "but model '#{model_name}' only has: #{model.capabilities.join(', ')}"
      end
    end

    def resolve_class(type_string)
      return try_constantize("Brainpipe::Operations::#{type_string}") ||
             try_constantize(type_string)
    end

    def try_constantize(class_name)
      names = class_name.split("::")
      names.reduce(Object) do |constant, name|
        constant.const_get(name, false)
      end
    rescue NameError
      nil
    end
  end
end
