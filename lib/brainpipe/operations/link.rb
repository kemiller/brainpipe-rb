module Brainpipe
  module Operations
    class Link < Operation
      def initialize(model: nil, options: {})
        @copy = normalize_field_mapping(options[:copy] || options["copy"])
        @move = normalize_field_mapping(options[:move] || options["move"])
        @set = normalize_set_values(options[:set] || options["set"])
        @delete = normalize_array(options[:delete] || options["delete"])

        unless @copy.any? || @move.any? || @set.any? || @delete.any?
          raise ConfigurationError, "Link requires at least one of: copy, move, set, delete"
        end

        super
      end

      def allows_count_change?
        false
      end

      def declared_reads(prefix_schema = {})
        reads = {}

        @copy.each_key do |source|
          type = prefix_schema.dig(source, :type)
          reads[source] = { type: type, optional: false }
        end

        @move.each_key do |source|
          type = prefix_schema.dig(source, :type)
          reads[source] = { type: type, optional: false }
        end

        reads
      end

      def declared_sets(prefix_schema = {})
        sets = {}

        @copy.each do |source, target|
          type = prefix_schema.dig(source, :type)
          sets[target] = { type: type, optional: false }
        end

        @move.each do |source, target|
          type = prefix_schema.dig(source, :type)
          sets[target] = { type: type, optional: false }
        end

        @set.each do |name, value|
          sets[name] = { type: infer_type(value), optional: false }
        end

        sets
      end

      def declared_deletes(prefix_schema = {})
        deletes = @delete.dup
        @move.each_key { |source| deletes << source }
        deletes.uniq
      end

      def create
        copy = @copy
        move = @move
        set = @set
        delete = @delete

        ->(namespaces) do
          namespaces.map do |ns|
            result = ns

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
      end

      private

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
