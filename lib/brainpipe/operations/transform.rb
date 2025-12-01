module Brainpipe
  module Operations
    class Transform < Operation
      def initialize(model: nil, options: {})
        warn "[DEPRECATION] Transform is deprecated. Use Link instead."
        @from = options[:from]&.to_sym
        @to = options[:to]&.to_sym
        @delete_source = options.fetch(:delete_source, false)

        raise ConfigurationError, "Transform requires 'from' option" unless @from
        raise ConfigurationError, "Transform requires 'to' option" unless @to

        super
      end

      def declared_reads(prefix_schema = {})
        type = prefix_schema.dig(@from, :type)
        { @from => { type: type, optional: false } }
      end

      def declared_sets(prefix_schema = {})
        type = prefix_schema.dig(@from, :type)
        { @to => { type: type, optional: false } }
      end

      def declared_deletes(prefix_schema = {})
        @delete_source ? [@from] : []
      end

      def create
        from = @from
        to = @to
        delete_source = @delete_source

        ->(namespaces) do
          namespaces.map do |ns|
            value = ns[from]
            result = ns.merge({ to => value })
            delete_source ? result.delete(from) : result
          end
        end
      end
    end
  end
end
