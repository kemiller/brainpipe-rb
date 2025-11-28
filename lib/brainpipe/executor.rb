require "timeout"

module Brainpipe
  class Executor
    attr_reader :callable, :operation, :debug, :timeout

    def initialize(callable, operation:, debug: false, timeout: nil)
      @callable = callable
      @operation = operation
      @debug = debug
      @timeout = timeout
    end

    def call(namespaces)
      namespaces.each { |ns| validate_reads!(ns) }

      before_states = namespaces.map(&:to_h)
      result, error_handled = execute_with_error_handling(namespaces)

      return result if error_handled

      validate_output_count!(namespaces, result)
      result.each_with_index do |ns, i|
        validate_sets!(before_states[i], ns)
        validate_deletes!(before_states[i], ns)
      end

      result
    end

    private

    def execute_with_error_handling(namespaces)
      result = if timeout
        execute_with_timeout(namespaces)
      else
        callable.call(namespaces)
      end
      [result, false]
    rescue => error
      handle_error(error)
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
