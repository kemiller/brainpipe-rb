module Brainpipe
  module Types
    class Any
      def self.===(other)
        true
      end
    end

    Boolean = Object.new
    def Boolean.===(value)
      value == true || value == false
    end
    def Boolean.inspect
      "Boolean"
    end
    def Boolean.to_s
      "Boolean"
    end
    Boolean.freeze

    class Optional
      attr_reader :type

      def initialize(type)
        @type = type
        freeze
      end

      def self.[](type)
        new(type)
      end

      def ===(value)
        value.nil? || TypeChecker.match?(value, @type)
      end

      def inspect
        "Optional[#{@type.inspect}]"
      end
    end

    class Enum
      attr_reader :values

      def initialize(*values)
        @values = values.freeze
        freeze
      end

      def self.[](*values)
        new(*values)
      end

      def ===(value)
        @values.include?(value)
      end

      def inspect
        "Enum[#{@values.map(&:inspect).join(", ")}]"
      end
    end

    class Union
      attr_reader :types

      def initialize(*types)
        @types = types.freeze
        freeze
      end

      def self.[](*types)
        new(*types)
      end

      def ===(value)
        @types.any? { |t| TypeChecker.match?(value, t) }
      end

      def inspect
        "Union[#{@types.map(&:inspect).join(", ")}]"
      end
    end
  end

  Any = Types::Any
  Boolean = Types::Boolean
  Optional = Types::Optional
  Enum = Types::Enum
  Union = Types::Union

  module TypeConstants
    Any = Types::Any
    Boolean = Types::Boolean
    Optional = Types::Optional
    Enum = Types::Enum
    Union = Types::Union
    Image = Brainpipe::Image
  end
end
