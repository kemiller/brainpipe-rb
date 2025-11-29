require "net/http"
require "json"
require "uri"

module Brainpipe
  module Operations
    class BamlRaw < Operation
      requires_model :image_edit

      def initialize(model: nil, options: {})
        @function_name = options[:function]&.to_sym
        @input_mapping = options[:inputs] || {}
        @output_mapping = options[:outputs] || {}
        @extractor = resolve_extractor(options[:image_extractor])
        @output_field = (options[:output_field] || :image).to_sym

        raise ConfigurationError, "BamlRaw operation requires 'function' option" unless @function_name
        raise ConfigurationError, "BamlRaw operation requires 'image_extractor' option" unless @extractor

        BamlAdapter.require_available!
        @baml_function = BamlAdapter.function(@function_name)

        super
      end

      def declared_reads(prefix_schema = {})
        reads = {}
        @input_mapping.each do |_baml_field, ns_field|
          ns_field_sym = ns_field.to_sym
          type = prefix_schema.dig(ns_field_sym, :type)
          reads[ns_field_sym] = { type: type, optional: false }
        end
        reads
      end

      def declared_sets(prefix_schema = {})
        sets = { @output_field => { type: Image, optional: false } }

        output_schema = @baml_function.output_schema
        if @output_mapping.empty?
          sets.merge!(output_schema)
        else
          @output_mapping.each do |baml_field, ns_field|
            baml_field_sym = baml_field.to_sym
            ns_field_sym = ns_field.to_sym
            type_info = output_schema[baml_field_sym] || { type: Any, optional: false }
            sets[ns_field_sym] = type_info
          end
        end

        sets
      end

      def declared_deletes(prefix_schema = {})
        []
      end

      def create
        function_name = @function_name
        input_mapping = @input_mapping
        output_mapping = @output_mapping
        extractor = @extractor
        output_field = @output_field
        model_config = @model

        ->(namespaces) do
          namespaces.map do |ns|
            input = build_input(ns, input_mapping)
            client_registry = model_config&.to_baml_client_registry

            result = execute_raw_request(function_name, input, client_registry)
            image = extractor.call(result[:raw_json])

            raise ExecutionError, "Extractor returned nil - no image found in response" unless image

            output = build_output(result[:parsed], output_mapping)
            output[output_field] = image

            ns.merge(output)
          end
        end
      end

      private

      def resolve_extractor(extractor_option)
        case extractor_option
        when nil
          nil
        when Symbol, String
          find_extractor_by_name(extractor_option.to_s)
        when Module, Class
          extractor_option
        when Proc
          extractor_option
        else
          raise ConfigurationError, "Invalid image_extractor: must be a name, module, or callable"
        end
      end

      def find_extractor_by_name(name)
        extractor_name = camelize(name)
        if Brainpipe::Extractors.const_defined?(extractor_name)
          Brainpipe::Extractors.const_get(extractor_name)
        else
          raise ConfigurationError, "Unknown extractor: #{name}. Available: #{available_extractors.join(', ')}"
        end
      end

      def available_extractors
        Brainpipe::Extractors.constants.map { |c| underscore(c.to_s) }
      end

      def camelize(str)
        str.to_s.split("_").map(&:capitalize).join
      end

      def underscore(str)
        str.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
           .gsub(/([a-z\d])([A-Z])/, '\1_\2')
           .downcase
      end

      def build_input(namespace, mapping)
        input = {}
        mapping.each do |baml_field, ns_field|
          value = namespace[ns_field.to_sym]
          input[baml_field.to_sym] = convert_value_for_baml(value)
        end
        input
      end

      def convert_value_for_baml(value)
        case value
        when Image
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
        when nil
          {}
        else
          if result.respond_to?(:to_h)
            result.to_h.transform_keys(&:to_sym)
          elsif result.respond_to?(:attributes)
            result.attributes.transform_keys(&:to_sym)
          else
            {}
          end
        end
      end

      def execute_raw_request(function_name, input, client_registry)
        client = BamlAdapter.baml_client

        request_builder = client.request
        unless request_builder.respond_to?(function_name)
          raise ExecutionError, "BAML request builder does not have method '#{function_name}'"
        end

        opts = client_registry ? { baml_options: { client_registry: client_registry } } : {}
        raw_request = request_builder.send(function_name, **input, **opts)

        url = raw_request.url
        headers = raw_request.headers || {}
        body = raw_request.body

        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"

        request = Net::HTTP::Post.new(uri.request_uri)
        headers.each { |k, v| request[k] = v }
        request.body = body.is_a?(String) ? body : body.to_json

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise ExecutionError, "HTTP request failed: #{response.code} #{response.message}"
        end

        raw_text = response.body
        parsed_output = raw_request.parse(raw_text)
        raw_json = JSON.parse(raw_text) rescue nil

        { raw_text: raw_text, raw_json: raw_json, parsed: parsed_output }
      end
    end
  end
end
