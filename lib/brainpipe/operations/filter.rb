module Brainpipe
  module Operations
    class Filter < Operation
      def initialize(model: nil, options: {})
        @field = options[:field]&.to_sym
        @value = options[:value]
        @condition = options[:condition]

        unless @condition || @field
          raise ConfigurationError, "Filter requires either 'condition' proc or 'field' option"
        end

        super
      end

      def declared_reads(prefix_schema = {})
        if @field
          type = prefix_schema.dig(@field, :type)
          { @field => { type: type, optional: false } }
        else
          {}
        end
      end

      def declared_sets(prefix_schema = {})
        {}
      end

      def declared_deletes(prefix_schema = {})
        []
      end

      def allows_count_change?
        true
      end

      def create
        field = @field
        value = @value
        condition = @condition

        ->(namespaces) do
          namespaces.select do |ns|
            if condition
              condition.call(ns)
            else
              ns[field] == value
            end
          end
        end
      end
    end
  end
end
