require "timeout"

module Brainpipe
  class Pipe
    attr_reader :name, :stages, :timeout, :metrics_collector

    def initialize(name:, stages:, timeout: nil, debug: false, metrics_collector: nil)
      @name = name.to_sym
      @stages = stages.freeze
      @timeout = timeout
      @debug = debug
      @metrics_collector = metrics_collector

      validate!

      @inputs = stages.first&.inputs&.dup&.freeze || {}.freeze
      @outputs = stages.last&.outputs&.dup&.freeze || {}.freeze

      freeze
    end

    def call(properties = nil, metrics_collector: nil, debugger: nil, **kwargs)
      properties = kwargs if properties.nil? && !kwargs.empty?
      raise EmptyInputError, "Pipe '#{name}' received empty properties" if properties.nil?

      effective_metrics = metrics_collector || @metrics_collector
      effective_debugger = debugger || (@debug ? Observability::Debug.new : nil)

      initial_namespace = properties.is_a?(Namespace) ? properties : Namespace.new(properties)
      start_time = monotonic_time

      emit_pipe_started(initial_namespace, effective_debugger, effective_metrics)

      begin
        result = if timeout
          execute_with_timeout(initial_namespace, effective_metrics, effective_debugger)
        else
          execute_pipeline(initial_namespace, effective_metrics, effective_debugger)
        end

        duration_ms = (monotonic_time - start_time) * 1000
        emit_pipe_completed(initial_namespace, result, duration_ms, effective_debugger, effective_metrics)
        result
      rescue => error
        duration_ms = (monotonic_time - start_time) * 1000
        emit_pipe_failed(error, duration_ms, effective_debugger, effective_metrics)
        raise
      end
    end

    private

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def emit_pipe_started(input, debugger, metrics_collector)
      debugger&.pipe_start(name, input)
      metrics_collector&.pipe_started(pipe: name, input: input)
    end

    def emit_pipe_completed(input, output, duration_ms, debugger, metrics_collector)
      operation_count = stages.sum { |s| s.operations.length }
      debugger&.pipe_end(name, output, duration_ms)
      metrics_collector&.pipe_completed(
        pipe: name,
        input: input,
        output: output,
        duration_ms: duration_ms,
        operations_count: operation_count
      )
    end

    def emit_pipe_failed(error, duration_ms, debugger, metrics_collector)
      debugger&.pipe_error(name, error, duration_ms)
      metrics_collector&.pipe_failed(pipe: name, error: error, duration_ms: duration_ms)
    end

    def execute_with_timeout(initial_namespace, metrics_collector, debugger)
      ::Timeout.timeout(timeout) { execute_pipeline(initial_namespace, metrics_collector, debugger) }
    rescue ::Timeout::Error, ::Timeout::ExitException => e
      raise TimeoutError, "Pipe '#{name}' timed out after #{timeout} seconds"
    end

    def execute_pipeline(initial_namespace, metrics_collector, debugger)
      namespaces = [initial_namespace]
      remaining_timeout = timeout

      stages.each do |stage|
        stage_timeout = compute_stage_timeout(stage, remaining_timeout)
        start_time = monotonic_time
        namespaces = stage.call(
          namespaces,
          timeout: stage_timeout,
          metrics_collector: metrics_collector,
          debugger: debugger,
          pipe_name: name
        )
        remaining_timeout -= (monotonic_time - start_time) if remaining_timeout
      end

      namespaces.first
    end

    def compute_stage_timeout(stage, remaining)
      return nil unless remaining
      return remaining unless stage.respond_to?(:timeout) && stage.timeout
      [stage.timeout, remaining].min
    end

    public

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
      prefix_schema = {}
      stages.each_with_index do |stage, index|
        stage.validate_parallel_type_consistency!(prefix_schema)

        if index < stages.length - 1
          validate_stage_pair!(stage, stages[index + 1], prefix_schema)
        end

        prefix_schema = compute_output_schema(prefix_schema, stage)
      end
    end

    def validate_stage_pair!(current_stage, next_stage, prefix_schema)
      output_schema = compute_output_schema(prefix_schema, current_stage)
      required_inputs = next_stage.aggregate_reads(output_schema).reject { |_, config| config[:optional] }

      missing = required_inputs.keys - output_schema.keys

      unless missing.empty?
        raise IncompatibleStagesError,
          "Stage '#{next_stage.name}' requires properties #{missing.map(&:inspect).join(', ')} " \
          "which are not provided by previous stages"
      end
    end

    def compute_output_schema(prefix_schema, stage)
      result = prefix_schema.dup

      stage.operations.each do |op|
        op.declared_deletes(prefix_schema).each { |name| result.delete(name) }
      end

      stage.aggregate_sets(prefix_schema).each do |name, config|
        result[name] = config
      end

      stage.aggregate_reads(prefix_schema).each do |name, config|
        result[name] = config unless result.key?(name)
      end

      result
    end

    def aggregate_available_properties(up_to_index)
      prefix_schema = {}

      stages[0..up_to_index].each do |stage|
        prefix_schema = compute_output_schema(prefix_schema, stage)
      end

      prefix_schema
    end
  end
end
