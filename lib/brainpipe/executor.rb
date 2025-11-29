require "timeout"

module Brainpipe
  class Executor
    attr_reader :callable, :operation, :debug, :timeout, :metrics_collector, :debugger,
                :stage_name, :pipe_name

    def initialize(callable, operation:, debug: false, timeout: nil, metrics_collector: nil,
                   debugger: nil, stage_name: nil, pipe_name: nil)
      @callable = callable
      @operation = operation
      @debug = debug
      @timeout = timeout
      @metrics_collector = metrics_collector
      @debugger = debugger
      @stage_name = stage_name
      @pipe_name = pipe_name
    end

    def call(namespaces)
      namespaces.each { |ns| validate_reads!(ns) }

      before_states = namespaces.map(&:to_h)
      start_time = monotonic_time

      emit_operation_started(namespaces)

      result, error_handled, error = execute_with_error_handling(namespaces)
      duration_ms = (monotonic_time - start_time) * 1000

      if error_handled
        emit_operation_completed(result, duration_ms)
        return result
      end

      if error
        emit_operation_failed(error, duration_ms)
        raise error
      end

      validate_output_count!(namespaces, result)
      result.each_with_index do |ns, i|
        validate_sets!(before_states[i], ns)
        validate_deletes!(before_states[i], ns)
      end

      emit_operation_completed(result, duration_ms)
      result
    end

    private

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def emit_operation_started(namespaces)
      debugger&.operation_start(operation_name, namespaces.first&.keys || [])
      metrics_collector&.operation_started(
        operation_class: operation.class,
        namespace: namespaces.first,
        stage: stage_name,
        pipe: pipe_name
      )
    end

    def emit_operation_completed(result, duration_ms)
      debugger&.operation_end(operation_name, duration_ms, result.first&.keys || [])
      metrics_collector&.operation_completed(
        operation_class: operation.class,
        namespace: result.first,
        duration_ms: duration_ms,
        stage: stage_name,
        pipe: pipe_name
      )
    end

    def emit_operation_failed(error, duration_ms)
      debugger&.operation_error(operation_name, error, duration_ms)
      metrics_collector&.operation_failed(
        operation_class: operation.class,
        namespace: nil,
        error: error,
        duration_ms: duration_ms,
        stage: stage_name,
        pipe: pipe_name
      )
    end

    def execute_with_error_handling(namespaces)
      result = if timeout
        execute_with_timeout(namespaces)
      else
        callable.call(namespaces)
      end
      [result, false, nil]
    rescue => error
      handled_result, was_handled = handle_error(error)
      if was_handled
        [handled_result, true, nil]
      else
        [nil, false, error]
      end
    end

    def execute_with_timeout(namespaces)
      ::Timeout.timeout(timeout) { callable.call(namespaces) }
    rescue ::Timeout::Error, ::Timeout::ExitException
      raise TimeoutError, "Operation #{operation_name} timed out after #{timeout} seconds"
    end

    def handle_error(error)
      handler = operation.error_handler

      case handler
      when true
        [[], true]
      when Proc
        raise error unless handler.call(error)
        [[], true]
      else
        raise error
      end
    end

    def validate_reads!(namespace)
      operation.declared_reads.each do |name, config|
        next if config[:optional]

        unless namespace.key?(name)
          raise PropertyNotFoundError,
            "Operation #{operation_name} expected to read '#{name}' but it was not found in namespace"
        end

        validate_type!(namespace[name], config[:type], name) if config[:type]
      end
    end

    def validate_sets!(before, after)
      operation.declared_sets.each do |name, config|
        next if config[:optional]

        unless after.key?(name)
          raise UnexpectedPropertyError,
            "Operation #{operation_name} declared it would set '#{name}' but it was not found in output"
        end

        validate_type!(after[name], config[:type], name) if config[:type]
      end
    end

    def validate_deletes!(before, after)
      operation.declared_deletes.each do |name|
        if after.key?(name)
          raise UnexpectedDeletionError,
            "Operation #{operation_name} declared it would delete '#{name}' but it still exists in output"
        end
      end
    end

    def validate_output_count!(input, output)
      return if operation.allows_count_change?
      return if input.length == output.length

      raise OutputCountMismatchError,
        "Operation #{operation_name} returned #{output.length} namespaces but received #{input.length}"
    end

    def validate_type!(value, type, property_name)
      TypeChecker.validate!(value, type, path: property_name.to_s)
    end

    def operation_name
      operation.class.name || "Anonymous Operation"
    end
  end
end
