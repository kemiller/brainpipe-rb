module Brainpipe
  module Operations
    class Merge < Operation
      def initialize(model: nil, options: {})
        warn "[DEPRECATION] Merge is deprecated. Use Collapse instead."
        @sources = Array(options[:sources]).map(&:to_sym)
        @target = options[:target]&.to_sym
        @combiner = options[:combiner] || ->(values) { values.join(" ") }
        @target_type = options[:target_type]
        @delete_sources = options.fetch(:delete_sources, false)

        raise ConfigurationError, "Merge requires 'sources' option with at least one field" if @sources.empty?
        raise ConfigurationError, "Merge requires 'target' option" unless @target
        raise ConfigurationError, "Merge requires 'target_type' option" unless @target_type

        super
      end

      def declared_reads(prefix_schema = {})
        @sources.each_with_object({}) do |source, reads|
          type = prefix_schema.dig(source, :type)
          reads[source] = { type: type, optional: false }
        end
      end

      def declared_sets(prefix_schema = {})
        { @target => { type: @target_type, optional: false } }
      end

      def declared_deletes(prefix_schema = {})
        @delete_sources ? @sources : []
      end

      def create
        sources = @sources
        target = @target
        combiner = @combiner
        delete_sources = @delete_sources

        ->(namespaces) do
          namespaces.map do |ns|
            values = sources.map { |s| ns[s] }
            combined = combiner.call(values)
            result = ns.merge({ target => combined })

            if delete_sources
              sources.each { |s| result = result.delete(s) }
            end

            result
          end
        end
      end
    end
  end
end
