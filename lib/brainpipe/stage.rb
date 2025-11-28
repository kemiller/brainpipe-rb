require "concurrent"

module Brainpipe
  class Stage
    MODES = [:merge, :fan_out, :batch].freeze
    MERGE_STRATEGIES = [:last_in, :first_in, :collate, :disjoint].freeze

    attr_reader :name, :mode, :operations, :merge_strategy

    def initialize(name:, mode:, operations:, merge_strategy: :last_in, debug: false)
      @name = name.to_sym
      @mode = validate_mode!(mode)
      @operations = operations.freeze
      @merge_strategy = validate_merge_strategy!(merge_strategy)
      @debug = debug

      validate_disjoint! if @merge_strategy == :disjoint

      @inputs = aggregate_reads.freeze
      @outputs = aggregate_sets.freeze

      freeze
    end

    def call(namespaces)
      raise EmptyInputError, "Stage '#{name}' received empty input" if namespaces.empty?

      case mode
      when :merge
        execute_merge(namespaces)
      when :fan_out
        execute_fan_out(namespaces)
      when :batch
        execute_batch(namespaces)
      end
    end

    attr_reader :inputs, :outputs

    def validate!
      validate_disjoint! if merge_strategy == :disjoint
      true
    end

    private

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

    def execute_merge(namespaces)
      merged = merge_namespaces(namespaces)
      results = execute_operations_parallel([merged])
      merge_operation_results(results)
    end

    def execute_fan_out(namespaces)
      results_per_namespace = namespaces.map.with_index do |ns, idx|
        [idx, execute_operations_parallel([ns])]
      end.to_h

      namespaces.each_index.map do |idx|
        op_results = results_per_namespace[idx]
        merge_operation_results(op_results).first
      end
    end

    def execute_batch(namespaces)
      results = execute_operations_parallel(namespaces)
      merge_batch_results(results, namespaces.length)
    end

    def execute_operations_parallel(namespaces)
      return [] if operations.empty?

      pool = Concurrent::FixedThreadPool.new([operations.length, 10].min)
      futures = []
      errors = Concurrent::Array.new

      operations.each do |operation|
        futures << Concurrent::Future.execute(executor: pool) do
          callable = operation.create
          executor = Executor.new(callable, operation: operation, debug: @debug)
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
