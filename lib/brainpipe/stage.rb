require "concurrent"
require "timeout"

module Brainpipe
  # A pipeline stage that groups operations for sequential execution.
  # Operations within a stage run in parallel and their results are merged.
  #
  # @example Creating a stage
  #   stage = Brainpipe::Stage.new(
  #     name: :process,
  #     operations: [Op1.new, Op2.new]
  #   )
  #
  class Stage
    # @return [Symbol] the stage name
    # @return [Array<Operation>] the operations to execute
    # @return [Numeric, nil] the timeout in seconds
    attr_reader :name, :operations, :timeout

    # Create a new stage.
    # @param name [Symbol, String] the stage name
    # @param operations [Array<Operation>] operations to execute
    # @param timeout [Numeric, nil] optional timeout in seconds
    # @param debug [Boolean] enable debug output
    def initialize(name:, operations:, timeout: nil, debug: false)
      @name = name.to_sym
      @operations = operations.freeze
      @timeout = timeout
      @debug = debug

      @inputs = aggregate_reads.freeze
      @outputs = aggregate_sets.freeze

      freeze
    end

    # Execute the stage with the given namespaces.
    # @param namespaces [Array<Namespace>] input namespaces
    # @param timeout [Numeric, nil] override timeout
    # @param metrics_collector [MetricsCollector, nil] metrics collector
    # @param debugger [Debug, nil] debugger instance
    # @param pipe_name [Symbol, nil] parent pipe name
    # @raise [EmptyInputError] if namespaces is empty
    # @raise [TimeoutError] if execution exceeds timeout
    # @return [Array<Namespace>] result namespaces
    def call(namespaces, timeout: nil, metrics_collector: nil, debugger: nil, pipe_name: nil)
      raise EmptyInputError, "Stage '#{name}' received empty input" if namespaces.empty?

      effective_timeout = compute_effective_timeout(timeout)
      start_time = monotonic_time

      emit_stage_started(namespaces, debugger, metrics_collector, pipe_name)

      begin
        result = if effective_timeout
          execute_with_timeout(namespaces, effective_timeout, metrics_collector, debugger, pipe_name)
        else
          execute_operations(namespaces, nil, metrics_collector, debugger, pipe_name)
        end

        duration_ms = (monotonic_time - start_time) * 1000
        emit_stage_completed(duration_ms, debugger, metrics_collector, pipe_name)
        result
      rescue => error
        duration_ms = (monotonic_time - start_time) * 1000
        emit_stage_failed(error, duration_ms, debugger, metrics_collector, pipe_name)
        raise
      end
    end

    attr_reader :inputs, :outputs

    def validate!
      true
    end

    def validate_parallel_type_consistency!(prefix_schema = {})
      type_by_field = {}

      operations.each do |op|
        op.declared_sets(prefix_schema).each do |name, config|
          type = config[:type]
          next unless type

          if type_by_field.key?(name)
            existing_type = type_by_field[name][:type]
            if existing_type != type
              raise TypeConflictError,
                "Stage '#{self.name}' has type conflict for field '#{name}': " \
                "#{type_by_field[name][:operation].class.name} sets #{existing_type.inspect}, " \
                "but #{op.class.name} sets #{type.inspect}"
            end
          else
            type_by_field[name] = { type: type, operation: op }
          end
        end
      end
    end

    def aggregate_reads(prefix_schema = {})
      operations.each_with_object({}) do |op, reads|
        op.declared_reads(prefix_schema).each do |name, config|
          next if reads.key?(name) && !config[:optional]
          reads[name] = config
        end
      end
    end

    def aggregate_sets(prefix_schema = {})
      operations.each_with_object({}) do |op, sets|
        op.declared_sets(prefix_schema).each do |name, config|
          next if sets.key?(name) && !config[:optional]
          sets[name] = config
        end
      end
    end

    private

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def emit_stage_started(namespaces, debugger, metrics_collector, pipe_name)
      debugger&.stage_start(name, namespaces.length)
      metrics_collector&.stage_started(
        stage: name,
        namespace_count: namespaces.length,
        pipe: pipe_name
      )
    end

    def emit_stage_completed(duration_ms, debugger, metrics_collector, pipe_name)
      debugger&.stage_end(name, duration_ms)
      metrics_collector&.stage_completed(
        stage: name,
        namespace_count: nil,
        duration_ms: duration_ms,
        pipe: pipe_name
      )
    end

    def emit_stage_failed(error, duration_ms, debugger, metrics_collector, pipe_name)
      debugger&.stage_error(name, error, duration_ms)
      metrics_collector&.stage_failed(
        stage: name,
        error: error,
        duration_ms: duration_ms,
        pipe: pipe_name
      )
    end

    def compute_effective_timeout(passed_timeout)
      return @timeout unless passed_timeout
      return passed_timeout unless @timeout
      [passed_timeout, @timeout].min
    end

    def execute_with_timeout(namespaces, timeout_value, metrics_collector, debugger, pipe_name)
      ::Timeout.timeout(timeout_value) { execute_operations(namespaces, timeout_value, metrics_collector, debugger, pipe_name) }
    rescue ::Timeout::Error, ::Timeout::ExitException
      raise TimeoutError, "Stage '#{name}' timed out after #{timeout_value} seconds"
    end

    def execute_operations(namespaces, timeout_value, metrics_collector, debugger, pipe_name)
      return namespaces if operations.empty?

      pool = Concurrent::FixedThreadPool.new([operations.length, 10].min)
      futures = []
      errors = Concurrent::Array.new

      operations.each do |operation|
        op_timeout = compute_operation_timeout(operation, timeout_value)
        futures << Concurrent::Future.execute(executor: pool) do
          callable = operation.create
          executor = Executor.new(
            callable,
            operation: operation,
            debug: @debug,
            timeout: op_timeout,
            metrics_collector: metrics_collector,
            debugger: debugger,
            stage_name: name,
            pipe_name: pipe_name
          )
          { operation: operation, result: executor.call(namespaces.map(&:dup)) }
        rescue Exception => e
          errors << e
          { operation: operation, error: e }
        end
      end

      results = futures.map do |future|
        future.wait
        if future.rejected?
          errors << future.reason unless errors.include?(future.reason)
          { operation: nil, error: future.reason }
        else
          future.value || { operation: nil, error: ExecutionError.new("Future completed with nil value") }
        end
      end
      pool.shutdown
      pool.wait_for_termination

      unless errors.empty?
        raise errors.first
      end

      merge_operation_results(results)
    end

    def compute_operation_timeout(operation, stage_timeout)
      op_timeout = operation.respond_to?(:timeout) ? operation.timeout : nil
      return op_timeout unless stage_timeout
      return stage_timeout unless op_timeout
      [op_timeout, stage_timeout].min
    end

    def merge_operation_results(results)
      successful = results.reject { |r| r[:error] }
      return [] if successful.empty?

      first_result = successful.first[:result]
      return first_result if successful.length == 1

      num_namespaces = first_result.length
      (0...num_namespaces).map do |idx|
        merge_results_at_index(successful, idx)
      end
    end

    def merge_results_at_index(results, idx)
      results.reduce(Namespace.new) do |merged, result|
        ns = result[:result][idx]
        merged.merge(ns.to_h)
      end
    end
  end
end
