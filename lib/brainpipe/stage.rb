require "concurrent"
require "timeout"

module Brainpipe
  class Stage
    MODES = [:merge, :fan_out, :batch].freeze
    MERGE_STRATEGIES = [:last_in, :first_in, :collate, :disjoint].freeze

    attr_reader :name, :mode, :operations, :merge_strategy, :timeout

    def initialize(name:, mode:, operations:, merge_strategy: :last_in, timeout: nil, debug: false)
      @name = name.to_sym
      @mode = validate_mode!(mode)
      @operations = operations.freeze
      @merge_strategy = validate_merge_strategy!(merge_strategy)
      @timeout = timeout
      @debug = debug

      validate_disjoint! if @merge_strategy == :disjoint

      @inputs = aggregate_reads.freeze
      @outputs = aggregate_sets.freeze

      freeze
    end

    def call(namespaces, timeout: nil)
      raise EmptyInputError, "Stage '#{name}' received empty input" if namespaces.empty?

      effective_timeout = compute_effective_timeout(timeout)

      if effective_timeout
        execute_with_timeout(namespaces, effective_timeout)
      else
        execute_stage(namespaces, nil)
      end
    end

    attr_reader :inputs, :outputs

    def validate!
      validate_disjoint! if merge_strategy == :disjoint
      true
    end

    private

    def compute_effective_timeout(passed_timeout)
      return @timeout unless passed_timeout
      return passed_timeout unless @timeout
      [passed_timeout, @timeout].min
    end

    def execute_with_timeout(namespaces, timeout_value)
      ::Timeout.timeout(timeout_value) { execute_stage(namespaces, timeout_value) }
    rescue ::Timeout::Error, ::Timeout::ExitException
      raise TimeoutError, "Stage '#{name}' timed out after #{timeout_value} seconds"
    end

    def execute_stage(namespaces, timeout_value)
      case mode
      when :merge
        execute_merge(namespaces, timeout_value)
      when :fan_out
        execute_fan_out(namespaces, timeout_value)
      when :batch
        execute_batch(namespaces, timeout_value)
      end
    end

    def validate_mode!(mode)
      mode = mode.to_sym
      unless MODES.include?(mode)
        raise ConfigurationError, "Invalid stage mode '#{mode}'. Valid modes: #{MODES.join(', ')}"
      end
      mode
    end

    def validate_merge_strategy!(strategy)
      strategy = strategy.to_sym
      unless MERGE_STRATEGIES.include?(strategy)
        raise ConfigurationError,
          "Invalid merge strategy '#{strategy}'. Valid strategies: #{MERGE_STRATEGIES.join(', ')}"
      end
      strategy
    end

    def validate_disjoint!
      all_sets = {}

      operations.each do |op|
        op.declared_sets.keys.each do |prop|
          if all_sets.key?(prop)
            raise ConfigurationError,
              "Disjoint merge strategy requires non-overlapping sets. " \
              "Property '#{prop}' is set by both #{all_sets[prop].class.name} and #{op.class.name}"
          end
          all_sets[prop] = op
        end
      end
    end

    def execute_merge(namespaces, timeout_value)
      merged = merge_namespaces(namespaces)
      results = execute_operations_parallel([merged], timeout_value)
      merge_operation_results(results)
    end

    def execute_fan_out(namespaces, timeout_value)
      results_per_namespace = namespaces.map.with_index do |ns, idx|
        [idx, execute_operations_parallel([ns], timeout_value)]
      end.to_h

      namespaces.each_index.map do |idx|
        op_results = results_per_namespace[idx]
        merge_operation_results(op_results).first
      end
    end

    def execute_batch(namespaces, timeout_value)
      results = execute_operations_parallel(namespaces, timeout_value)
      merge_batch_results(results, namespaces.length)
    end

    def execute_operations_parallel(namespaces, timeout_value)
      return [] if operations.empty?

      pool = Concurrent::FixedThreadPool.new([operations.length, 10].min)
      futures = []
      errors = Concurrent::Array.new

      operations.each do |operation|
        op_timeout = compute_operation_timeout(operation, timeout_value)
        futures << Concurrent::Future.execute(executor: pool) do
          callable = operation.create
          executor = Executor.new(callable, operation: operation, debug: @debug, timeout: op_timeout)
          { operation: operation, result: executor.call(namespaces.map(&:dup)) }
        rescue => e
          errors << e
          { operation: operation, error: e }
        end
      end

      results = futures.map(&:value)
      pool.shutdown
      pool.wait_for_termination

      unless errors.empty?
        raise errors.first
      end

      results
    end

    def compute_operation_timeout(operation, stage_timeout)
      op_timeout = operation.respond_to?(:timeout) ? operation.timeout : nil
      return op_timeout unless stage_timeout
      return stage_timeout unless op_timeout
      [op_timeout, stage_timeout].min
    end

    def merge_namespaces(namespaces)
      namespaces.reduce(Namespace.new) do |merged, ns|
        merged.merge(ns.to_h)
      end
    end

    def merge_operation_results(results)
      return [Namespace.new] if results.empty?

      successful = results.reject { |r| r[:error] }
      return [Namespace.new] if successful.empty?

      first_result = successful.first[:result]
      return first_result if successful.length == 1

      num_namespaces = first_result.length
      (0...num_namespaces).map do |idx|
        merge_at_index(successful, idx)
      end
    end

    def merge_at_index(results, idx)
      case merge_strategy
      when :last_in
        merge_last_in(results, idx)
      when :first_in
        merge_first_in(results, idx)
      when :collate
        merge_collate(results, idx)
      when :disjoint
        merge_disjoint(results, idx)
      end
    end

    def merge_last_in(results, idx)
      results.reduce(Namespace.new) do |merged, result|
        ns = result[:result][idx]
        merged.merge(ns.to_h)
      end
    end

    def merge_first_in(results, idx)
      results.reverse.reduce(Namespace.new) do |merged, result|
        ns = result[:result][idx]
        merged.merge(ns.to_h)
      end
    end

    def merge_collate(results, idx)
      all_props = {}

      results.each do |result|
        ns = result[:result][idx]
        ns.keys.each do |key|
          all_props[key] ||= []
          all_props[key] << ns[key]
        end
      end

      collapsed = all_props.transform_values do |values|
        values.uniq.length == 1 ? values.first : values
      end

      Namespace.new(collapsed)
    end

    def merge_disjoint(results, idx)
      results.reduce(Namespace.new) do |merged, result|
        ns = result[:result][idx]
        merged.merge(ns.to_h)
      end
    end

    def merge_batch_results(results, expected_length)
      return Array.new(expected_length) { Namespace.new } if results.empty?

      successful = results.reject { |r| r[:error] }
      return Array.new(expected_length) { Namespace.new } if successful.empty?

      first_result = successful.first[:result]
      return first_result if successful.length == 1

      num_namespaces = first_result.length
      (0...num_namespaces).map do |idx|
        merge_at_index(successful, idx)
      end
    end

    def aggregate_reads
      operations.each_with_object({}) do |op, reads|
        op.declared_reads.each do |name, config|
          next if reads.key?(name) && !config[:optional]
          reads[name] = config
        end
      end
    end

    def aggregate_sets
      operations.each_with_object({}) do |op, sets|
        op.declared_sets.each do |name, config|
          next if sets.key?(name) && !config[:optional]
          sets[name] = config
        end
      end
    end
  end
end
