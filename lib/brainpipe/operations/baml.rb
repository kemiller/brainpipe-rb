module Brainpipe
  module Operations
    class Baml < Operation
      requires_model :text_to_text

      def initialize(model: nil, options: {})
        @function_name = options[:function]&.to_sym
        @input_mapping = options[:inputs] || {}
        @output_mapping = options[:outputs] || {}

        raise ConfigurationError, "Baml operation requires 'function' option" unless @function_name

        BamlAdapter.require_available!
        @baml_function = BamlAdapter.function(@function_name)

        super
      end

      def declared_reads(prefix_schema = {})
        if @input_mapping.empty?
          @baml_function.input_schema
        else
          reads = {}
          @input_mapping.each do |_baml_field, ns_field|
            ns_field_sym = ns_field.to_sym
            type = prefix_schema.dig(ns_field_sym, :type)
            reads[ns_field_sym] = { type: type, optional: false }
          end
          reads
        end
      end

      def declared_sets(prefix_schema = {})
        output_schema = @baml_function.output_schema

        if @output_mapping.empty?
          output_schema
        else
          sets = {}
          @output_mapping.each do |baml_field, ns_field|
            baml_field_sym = baml_field.to_sym
            ns_field_sym = ns_field.to_sym
            type_info = output_schema[baml_field_sym] || { type: Any, optional: false }
            sets[ns_field_sym] = type_info
          end
          sets
        end
      end

      def declared_deletes(prefix_schema = {})
        []
      end

      def create
        baml_function = @baml_function
        model_config = @model
        input_mapping = @input_mapping
        output_mapping = @output_mapping

        ->(namespaces) do
          namespaces.map do |ns|
            input = build_input(ns, baml_function, input_mapping)
            client_registry = model_config&.to_baml_client_registry

            result = baml_function.call(input, client_registry: client_registry)
            output = build_output(result, output_mapping)

            ns.merge(output)
          end
        end
      end

      private

      def build_input(namespace, baml_function, mapping)
        if mapping.empty?
          input = {}
          baml_function.input_schema.each_key do |field|
            input[field] = convert_for_baml(namespace[field])
          end
          input
        else
          input = {}
          mapping.each do |baml_field, ns_field|
            input[baml_field.to_sym] = convert_for_baml(namespace[ns_field.to_sym])
          end
          input
        end
      end

      def convert_for_baml(value)
        case value
        when Brainpipe::Image
          value.to_baml_image
        else
          value
        end
      end

      def build_output(result, mapping)
        result_hash = result_to_hash(result)

        if mapping.empty?
          result_hash
        else
          output = {}
          mapping.each do |baml_field, ns_field|
            output[ns_field.to_sym] = result_hash[baml_field.to_sym]
          end
          output
        end
      end

      def result_to_hash(result)
        case result
        when Hash
          result.transform_keys(&:to_sym)
        else
          if result.respond_to?(:to_h)
            result.to_h.transform_keys(&:to_sym)
          elsif result.respond_to?(:attributes)
            result.attributes.transform_keys(&:to_sym)
          else
            result
          end
        end
      end
    end
  end
end
