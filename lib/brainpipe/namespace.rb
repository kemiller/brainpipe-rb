module Brainpipe
  # An immutable property bag that flows through pipelines.
  # All operations receive and return Namespace instances.
  #
  # @example Creating a namespace
  #   ns = Brainpipe::Namespace.new(name: "Alice", age: 30)
  #   ns[:name]  # => "Alice"
  #
  # @example Merging creates a new namespace
  #   new_ns = ns.merge(city: "NYC")
  #   new_ns[:city]  # => "NYC"
  #   ns[:city]      # => nil (original unchanged)
  #
  class Namespace
    # @param properties [Hash] initial properties
    def initialize(properties = {})
      @data = properties.transform_keys(&:to_sym).freeze
      freeze
    end

    # Access a property by key.
    # @param key [Symbol, String] the property name
    # @return [Object, nil] the property value
    def [](key)
      @data[key.to_sym]
    end

    # Create a new namespace with additional properties merged in.
    # @param properties [Hash] properties to merge
    # @return [Namespace] a new namespace instance
    def merge(properties)
      Namespace.new(@data.merge(properties.transform_keys(&:to_sym)))
    end

    # Create a new namespace with specified keys removed.
    # @param keys [Array<Symbol, String>] keys to delete
    # @return [Namespace] a new namespace instance
    def delete(*keys)
      keys_to_delete = keys.map(&:to_sym)
      Namespace.new(@data.reject { |k, _| keys_to_delete.include?(k) })
    end

    # Convert to a hash.
    # @return [Hash] a copy of the internal data
    def to_h
      @data.dup
    end

    # Get all property names.
    # @return [Array<Symbol>] the property keys
    def keys
      @data.keys
    end

    # Check if a property exists.
    # @param key [Symbol, String] the property name
    # @return [Boolean]
    def key?(key)
      @data.key?(key.to_sym)
    end

    def ==(other)
      return false unless other.is_a?(Namespace)
      to_h == other.to_h
    end

    def eql?(other)
      self == other
    end

    def hash
      @data.hash
    end

    def inspect
      "#<Brainpipe::Namespace #{@data.inspect}>"
    end
  end
end
