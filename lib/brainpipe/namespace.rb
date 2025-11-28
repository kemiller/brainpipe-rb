module Brainpipe
  class Namespace
    def initialize(properties = {})
      @data = properties.transform_keys(&:to_sym).freeze
      freeze
    end

    def [](key)
      @data[key.to_sym]
    end

    def merge(properties)
      Namespace.new(@data.merge(properties.transform_keys(&:to_sym)))
    end

    def delete(*keys)
      keys_to_delete = keys.map(&:to_sym)
      Namespace.new(@data.reject { |k, _| keys_to_delete.include?(k) })
    end

    def to_h
      @data.dup
    end

    def keys
      @data.keys
    end

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
