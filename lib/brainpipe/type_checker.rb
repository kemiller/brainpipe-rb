module Brainpipe
  module TypeChecker
    class << self
      def validate!(value, type, path: "")
        return if match?(value, type)
        raise TypeMismatchError, format_error(value, type, path)
      end

      def match?(value, type)
        if type == Types::Any || type == Any
          true
        elsif type.is_a?(Types::Optional)
          value.nil? || match?(value, type.type)
        elsif type.is_a?(Types::Enum)
          type.values.include?(value)
        elsif type.is_a?(Types::Union)
          type.types.any? { |t| match?(value, t) }
        elsif type == Boolean || type == Types::Boolean
          value == true || value == false
        elsif type.is_a?(Class)
          value.is_a?(type)
        elsif type.is_a?(Array)
          match_array?(value, type)
        elsif type.is_a?(Hash)
          match_hash?(value, type)
        else
          type === value
        end
      end

      def validate_structure!(value, schema, path: "")
        if schema.is_a?(Hash) && !typed_hash?(schema)
          validate_hash_structure!(value, schema, path)
        elsif schema.is_a?(Array)
          validate_array_structure!(value, schema, path)
        else
          validate!(value, schema, path: path)
        end
      end

      private

      def match_array?(value, type)
        return false unless value.is_a?(Array)
        return true if type.empty?
        element_type = type.first
        value.all? { |v| match?(v, element_type) }
      end

      def match_hash?(value, type)
        return false unless value.is_a?(Hash)

        if typed_hash?(type)
          match_typed_hash?(value, type)
        else
          match_object_structure?(value, type)
        end
      end

      def typed_hash?(type)
        return false unless type.is_a?(Hash)
        return false if type.empty?
        type.keys.all? { |k| k.is_a?(Class) || k == Boolean }
      end

      def match_typed_hash?(value, type)
        key_type, value_type = type.first
        value.all? do |k, v|
          match?(k, key_type) && match?(v, value_type)
        end
      end

      def match_object_structure?(value, schema)
        schema.all? do |key, type|
          key_str = key.to_s
          optional = key_str.end_with?("?")
          actual_key = optional ? key_str.chomp("?").to_sym : key.to_sym

          if value.key?(actual_key)
            match?(value[actual_key], type)
          else
            optional
          end
        end
      end

      def validate_hash_structure!(value, schema, path)
        unless value.is_a?(Hash)
          raise TypeMismatchError, "#{path_prefix(path)}expected Hash, got #{value.class}"
        end

        if typed_hash?(schema)
          validate_typed_hash!(value, schema, path)
        else
          validate_object_structure!(value, schema, path)
        end
      end

      def validate_typed_hash!(value, schema, path)
        key_type, value_type = schema.first
        value.each do |k, v|
          key_path = "#{path}[#{k.inspect}]"
          validate!(k, key_type, path: "#{key_path} (key)")
          validate!(v, value_type, path: key_path)
        end
      end

      def validate_object_structure!(value, schema, path)
        schema.each do |key, type|
          key_str = key.to_s
          optional = key_str.end_with?("?")
          actual_key = optional ? key_str.chomp("?").to_sym : key.to_sym
          field_path = path.empty? ? actual_key.to_s : "#{path}.#{actual_key}"

          if value.key?(actual_key)
            validate_structure!(value[actual_key], type, path: field_path)
          elsif !optional
            raise TypeMismatchError, "#{field_path} is required but missing"
          end
        end
      end

      def validate_array_structure!(value, schema, path)
        unless value.is_a?(Array)
          raise TypeMismatchError, "#{path_prefix(path)}expected Array, got #{value.class}"
        end

        return if schema.empty?

        element_type = schema.first
        value.each_with_index do |v, i|
          element_path = "#{path}[#{i}]"
          validate_structure!(v, element_type, path: element_path)
        end
      end

      def format_error(value, type, path)
        "#{path_prefix(path)}expected #{type_name(type)}, got #{value_description(value)}"
      end

      def path_prefix(path)
        path.empty? ? "" : "#{path}: "
      end

      def type_name(type)
        if type.is_a?(Types::Optional) || type.is_a?(Types::Enum) || type.is_a?(Types::Union)
          type.inspect
        elsif type == Types::Any || type == Any
          "Any"
        elsif type == Boolean || type == Types::Boolean
          "Boolean"
        elsif type.is_a?(Class)
          type.name
        elsif type.is_a?(Array)
          type.empty? ? "Array" : "[#{type_name(type.first)}]"
        elsif type.is_a?(Hash)
          if typed_hash?(type)
            key_type, value_type = type.first
            "{ #{type_name(key_type)} => #{type_name(value_type)} }"
          else
            "{ #{type.map { |k, v| "#{k}: #{type_name(v)}" }.join(", ")} }"
          end
        else
          type.inspect
        end
      end

      def value_description(value)
        case value
        when nil
          "nil"
        when String
          value.length > 50 ? "String(#{value.length} chars)" : value.inspect
        when Array
          "Array(#{value.length} elements)"
        when Hash
          "Hash(#{value.keys.join(", ")})"
        else
          "#{value.class.name}(#{value.inspect})"
        end
      end
    end
  end
end
