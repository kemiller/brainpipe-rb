module Brainpipe
  module Operations
    class Explode < Operation
      VALID_ON_EMPTY = [:skip, :error].freeze

      def initialize(model: nil, options: {})
        @split = normalize_field_mapping(options[:split] || options["split"])
        @on_empty = (options[:on_empty] || options["on_empty"] || :skip).to_sym
        @copy = normalize_field_mapping(options[:copy] || options["copy"])
        @move = normalize_field_mapping(options[:move] || options["move"])
        @set = normalize_set_values(options[:set] || options["set"])
        @delete = normalize_array(options[:delete] || options["delete"])

        unless @split.any?
          raise ConfigurationError, "Explode requires 'split' option"
        end

        unless VALID_ON_EMPTY.include?(@on_empty)
          raise ConfigurationError, "Explode: invalid on_empty value '#{@on_empty}'. " \
            "Valid values: #{VALID_ON_EMPTY.join(', ')}"
        end

        super
      end

      def allows_count_change?
        true
      end

      def declared_reads(prefix_schema = {})
        reads = {}

        @split.each_key do |source|
          type = prefix_schema.dig(source, :type)
          reads[source] = { type: type, optional: false }
        end

        reads
      end

      def declared_sets(prefix_schema = {})
        sets = {}
        split_sources = @split.keys

        prefix_schema.each do |name, config|
          next if split_sources.include?(name)
          sets[name] = config.dup
        end

        @split.each do |source, target|
          source_type = prefix_schema.dig(source, :type)
          element_type = unwrap_array_type(source_type)
          sets[target] = { type: element_type, optional: false }
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
        deletes = @split.keys.dup
        deletes.concat(@delete)
        @move.each_key { |source| deletes << source }
        deletes.uniq
      end

      def create
        split = @split
        on_empty = @on_empty
        copy = @copy
        move = @move
        set = @set
        delete = @delete

        ->(namespaces) do
          namespaces.flat_map do |ns|
            explode_namespace(ns, split, on_empty, copy, move, set, delete)
          end
        end
      end

      private

      def explode_namespace(ns, split, on_empty, copy, move, set, delete)
        first_source = split.keys.first
        first_array = ns[first_source] || []

        if first_array.empty?
          if on_empty == :error
            raise ExecutionError, "Explode: empty array in field '#{first_source}'"
          end
          return []
        end

        cardinality = first_array.length
        split.each do |source, _target|
          arr = ns[source] || []
          if arr.length != cardinality
            raise ExecutionError, "Explode: mismatched cardinalities. " \
              "Field '#{first_source}' has #{cardinality} elements, " \
              "but '#{source}' has #{arr.length}"
          end
        end

        non_split_keys = ns.keys - split.keys
        non_split_data = non_split_keys.each_with_object({}) { |k, h| h[k] = ns[k] }

        (0...cardinality).map do |idx|
          result_data = non_split_data.dup

          split.each do |source, target|
            result_data[target] = ns[source][idx]
          end

          result = Namespace.new(result_data)

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

          result
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

      def unwrap_array_type(type)
        return nil unless type
        return type.first if type.is_a?(Array) && type.length == 1
        type
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
