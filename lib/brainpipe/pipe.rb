module Brainpipe
  class Pipe
    attr_reader :name, :stages, :timeout

    def initialize(name:, stages:, timeout: nil, debug: false)
      @name = name.to_sym
      @stages = stages.freeze
      @timeout = timeout
      @debug = debug

      validate!

      @inputs = stages.first&.inputs&.dup&.freeze || {}.freeze
      @outputs = stages.last&.outputs&.dup&.freeze || {}.freeze

      freeze
    end

    def call(properties)
      raise EmptyInputError, "Pipe '#{name}' received empty properties" if properties.nil?

      initial_namespace = properties.is_a?(Namespace) ? properties : Namespace.new(properties)
      namespaces = [initial_namespace]

      stages.each do |stage|
        namespaces = stage.call(namespaces)
      end

      namespaces.first
    end

    attr_reader :inputs, :outputs

    def validate!
      validate_has_stages!
      validate_last_stage_mode!
      validate_stage_compatibility!
      true
    end

    private

    def validate_has_stages!
      if stages.empty?
        raise ConfigurationError, "Pipe '#{name}' must have at least one stage"
      end
    end

    def validate_last_stage_mode!
      return if stages.empty?

      unless stages.last.mode == :merge
        raise ConfigurationError,
          "Pipe '#{name}' last stage must be merge mode, got '#{stages.last.mode}'"
      end
    end

    def validate_stage_compatibility!
      return if stages.length < 2

      stages.each_cons(2).with_index do |(current_stage, next_stage), index|
        validate_stage_pair!(current_stage, next_stage, index)
      end
    end

    def validate_stage_pair!(current_stage, next_stage, index)
      available_outputs = aggregate_available_properties(index)
      required_inputs = next_stage.inputs.reject { |_, config| config[:optional] }

      missing = required_inputs.keys - available_outputs.keys

      unless missing.empty?
        raise IncompatibleStagesError,
          "Stage '#{next_stage.name}' requires properties #{missing.map(&:inspect).join(', ')} " \
          "which are not provided by previous stages"
      end
    end

    def aggregate_available_properties(up_to_index)
      properties = {}

      stages[0..up_to_index].each do |stage|
        stage.outputs.each do |name, config|
          properties[name] = config unless config[:optional]
        end

        stage.inputs.each do |name, config|
          properties[name] = config unless properties.key?(name)
        end
      end

      properties
    end
  end
end
