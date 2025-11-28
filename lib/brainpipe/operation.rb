module Brainpipe
  class Operation
    class << self
      def inherited(subclass)
        subclass.instance_variable_set(:@_reads, {})
        subclass.instance_variable_set(:@_sets, {})
        subclass.instance_variable_set(:@_deletes, [])
        subclass.instance_variable_set(:@_required_model_capability, nil)
        subclass.instance_variable_set(:@_error_handler, nil)
        subclass.instance_variable_set(:@_execute_block, nil)
      end

      def reads(name, type = nil, optional: false)
        @_reads ||= {}
        @_reads[name.to_sym] = { type: type, optional: optional }
      end

      def sets(name, type = nil, optional: false)
        @_sets ||= {}
        @_sets[name.to_sym] = { type: type, optional: optional }
      end

      def deletes(name)
        @_deletes ||= []
        @_deletes << name.to_sym
      end

      def requires_model(capability)
        @_required_model_capability = capability.to_sym
      end

      def ignore_errors(value = nil, &block)
        @_error_handler = block_given? ? block : value
      end

      def execute(&block)
        @_execute_block = block
      end

      def _reads
        @_reads ||= {}
      end

      def _sets
        @_sets ||= {}
      end

      def _deletes
        @_deletes ||= []
      end

      def _required_model_capability
        @_required_model_capability
      end

      def _error_handler
        @_error_handler
      end

      def _execute_block
        @_execute_block
      end
    end

    attr_reader :model, :options

    def initialize(model: nil, options: {})
      @model = model
      @options = options.freeze
      freeze
    end

    def declared_reads
      self.class._reads.dup
    end

    def declared_sets
      self.class._sets.dup
    end

    def declared_deletes
      self.class._deletes.dup
    end

    def required_model_capability
      self.class._required_model_capability
    end

    def error_handler
      self.class._error_handler
    end

    def create
      execute_block = self.class._execute_block
      operation = self

      if execute_block
        ->(namespaces) do
          namespaces.map do |ns|
            result = operation.instance_exec(ns, &execute_block)
            result.is_a?(Namespace) ? result : ns.merge(result || {})
          end
        end
      else
        ->(namespaces) { operation.call(namespaces) }
      end
    end

    def call(namespaces)
      namespaces
    end
  end
end
