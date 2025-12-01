module Brainpipe
  # Base class for pipeline operations. Subclass this to define custom operations.
  #
  # @example Simple operation with execute block
  #   class MyOp < Brainpipe::Operation
  #     reads :input, String
  #     sets :output, String
  #
  #     execute do |ns|
  #       { output: ns[:input].upcase }
  #     end
  #   end
  #
  # @example Operation with full control via call method
  #   class BatchOp < Brainpipe::Operation
  #     reads :items, [String]
  #     sets :processed, [String]
  #
  #     def call(namespaces)
  #       namespaces.map do |ns|
  #         ns.merge(processed: ns[:items].map(&:upcase))
  #       end
  #     end
  #   end
  #
  class Operation
    include TypeConstants

    class << self
      def inherited(subclass)
        subclass.include(TypeConstants)
        subclass.instance_variable_set(:@_reads, {})
        subclass.instance_variable_set(:@_sets, {})
        subclass.instance_variable_set(:@_deletes, [])
        subclass.instance_variable_set(:@_required_model_capability, nil)
        subclass.instance_variable_set(:@_error_handler, nil)
        subclass.instance_variable_set(:@_execute_block, nil)
        subclass.instance_variable_set(:@_timeout, nil)
      end

      # Declare a property this operation reads from the namespace.
      # @param name [Symbol, String] the property name
      # @param type [Class, nil] the expected type (optional)
      # @param optional [Boolean] whether the property is optional
      def reads(name, type = nil, optional: false)
        @_reads ||= {}
        @_reads[name.to_sym] = { type: type, optional: optional }
      end

      # Declare a property this operation sets on the namespace.
      # @param name [Symbol, String] the property name
      # @param type [Class, nil] the expected type (optional)
      # @param optional [Boolean] whether setting is optional
      def sets(name, type = nil, optional: false)
        @_sets ||= {}
        @_sets[name.to_sym] = { type: type, optional: optional }
      end

      # Declare a property this operation deletes from the namespace.
      # @param name [Symbol, String] the property name
      def deletes(name)
        @_deletes ||= []
        @_deletes << name.to_sym
      end

      # Require a model with a specific capability.
      # @param capability [Symbol] the required capability (e.g., :text_to_text)
      def requires_model(capability)
        @_required_model_capability = capability.to_sym
      end

      # Configure error handling for this operation.
      # @param value [Boolean, nil] true to ignore all errors
      # @yield [error] block to determine if error should be ignored
      # @yieldparam error [Exception] the error that occurred
      # @yieldreturn [Boolean] true to ignore the error
      def ignore_errors(value = nil, &block)
        @_error_handler = block_given? ? block : value
      end

      # Set a timeout for this operation in seconds.
      # @param value [Numeric] timeout in seconds
      def timeout(value)
        @_timeout = value
      end

      # Define the execution logic for this operation.
      # @yield [namespace] block called for each namespace
      # @yieldparam namespace [Namespace] the input namespace
      # @yieldreturn [Hash, Namespace] properties to merge or new namespace
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

      def _timeout
        @_timeout
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

    def declared_reads(prefix_schema = {})
      self.class._reads.dup
    end

    def declared_sets(prefix_schema = {})
      self.class._sets.dup
    end

    def declared_deletes(prefix_schema = {})
      self.class._deletes.dup
    end

    def required_model_capability
      self.class._required_model_capability
    end

    def allows_count_change?
      false
    end

    def error_handler
      self.class._error_handler
    end

    def timeout
      self.class._timeout || options[:timeout]
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
