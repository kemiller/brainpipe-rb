module Brainpipe
  module Operations
    class Collapse < Operation
      MERGE_STRATEGIES = [:collect, :sum, :concat, :first, :last, :equal, :distinct].freeze

      def initialize(model: nil, options: {})
        @merge_strategies = normalize_strategies(options[:merge] || options["merge"])
        @copy = normalize_field_mapping(options[:copy] || options["copy"])
        @move = normalize_field_mapping(options[:move] || options["move"])
        @set = normalize_set_values(options[:set] || options["set"])
        @delete = normalize_array(options[:delete] || options["delete"])

        super
      end

      def allows_count_change?
        true
      end

      def declared_reads(prefix_schema = {})
        prefix_schema.dup
      end

      def declared_sets(prefix_schema = {})
        sets = {}

        prefix_schema.each do |name, config|
          strategy = @merge_strategies[name] || :equal
          type = config[:type]

          if [:collect, :distinct].include?(strategy) && type
            sets[name] = { type: [type], optional: config[:optional] }
          else
            sets[name] = config.dup
          end
        end

        @copy.each do |source, target|
          source_config = sets[source] || prefix_schema[source]
          sets[target] = source_config.dup if source_config
        end

        @move.each do |source, target|
          source_config = sets[source] || prefix_schema[source]
          if source_config
            sets[target] = source_config.dup
            sets.delete(source)
          end
        end

        @set.each do |name, value|
          sets[name] = { type: infer_type(value), optional: false }
        end

        @delete.each { |name| sets.delete(name) }

        sets
      end

      def declared_deletes(prefix_schema = {})
        deletes = @delete.dup
        @move.each_key { |source| deletes << source }
        deletes.uniq
      end

      def create
        merge_strategies = @merge_strategies
        copy = @copy
        move = @move
        set = @set
        delete = @delete

        ->(namespaces) do
          return [Namespace.new] if namespaces.empty?

          all_keys = namespaces.flat_map(&:keys).uniq
          merged = {}

          all_keys.each do |key|
            next if delete.include?(key)
            values = namespaces.map { |ns| ns[key] }.compact
            next if values.empty?

            strategy = merge_strategies[key] || :equal
            merged[key] = apply_strategy(strategy, values, key)
          end

          result = Namespace.new(merged)

          copy.each do |source, target|
            result = result.merge({ target => result[source] })
          end

          move.each do |source, target|
            value = result[source]
            result = result.merge({ target => value })
            result = result.delete(source)
          end

          set.each do |name, value|
            result = result.merge({ name => value })
          end

          delete.each do |name|
            result = result.delete(name)
          end

          [result]
        end
      end

      private

      def apply_strategy(strategy, values, field_name)
        case strategy
        when :collect
          values
        when :sum
          values.reduce(0) { |sum, v| sum + v }
        when :concat
          if values.first.is_a?(Array)
            values.reduce([]) { |acc, v| acc + v }
          else
            values.join
          end
        when :first
          values.first
        when :last
          values.last
        when :equal
          if values.uniq.length > 1
            raise ExecutionError, "Collapse: conflicting values for field '#{field_name}': #{values.inspect}"
          end
          values.first
        when :distinct
          if values.length != values.uniq.length
            raise ExecutionError, "Collapse: duplicate values for field '#{field_name}': #{values.inspect}"
          end
          values
        else
          values.first
        end
      end

      def normalize_strategies(value)
        return {} unless value

        value.each_with_object({}) do |(k, v), h|
          strategy = v.to_sym
          unless MERGE_STRATEGIES.include?(strategy)
            raise ConfigurationError, "Collapse: unknown merge strategy '#{strategy}'. " \
              "Valid strategies: #{MERGE_STRATEGIES.join(', ')}"
          end
          h[k.to_sym] = strategy
        end
      end

      def normalize_field_mapping(value)
        return {} unless value

        value.each_with_object({}) do |(k, v), h|
          h[k.to_sym] = v.to_sym
        end
      end

      def normalize_set_values(value)
        return {} unless value

        value.each_with_object({}) do |(k, v), h|
          h[k.to_sym] = v
        end
      end

      def normalize_array(value)
        return [] unless value

        Array(value).map(&:to_sym)
      end

      def infer_type(value)
        case value
        when String then String
        when Integer then Integer
        when Float then Float
        when TrueClass then TrueClass
        when FalseClass then FalseClass
        when Array then Array
        when Hash then Hash
        when NilClass then NilClass
        else value.class
        end
      end
    end
  end
end
