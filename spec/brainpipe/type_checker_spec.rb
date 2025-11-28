RSpec.describe Brainpipe::TypeChecker do
  describe ".match?" do
    context "basic types" do
      it "matches String" do
        expect(described_class.match?("hello", String)).to be true
        expect(described_class.match?(123, String)).to be false
        expect(described_class.match?(nil, String)).to be false
      end

      it "matches Integer" do
        expect(described_class.match?(42, Integer)).to be true
        expect(described_class.match?(42.0, Integer)).to be false
        expect(described_class.match?("42", Integer)).to be false
      end

      it "matches Float" do
        expect(described_class.match?(3.14, Float)).to be true
        expect(described_class.match?(42, Float)).to be false
      end

      it "matches Symbol" do
        expect(described_class.match?(:foo, Symbol)).to be true
        expect(described_class.match?("foo", Symbol)).to be false
      end

      it "matches Boolean" do
        expect(described_class.match?(true, Brainpipe::Boolean)).to be true
        expect(described_class.match?(false, Brainpipe::Boolean)).to be true
        expect(described_class.match?(nil, Brainpipe::Boolean)).to be false
        expect(described_class.match?("true", Brainpipe::Boolean)).to be false
      end
    end

    context "Any type" do
      it "matches anything" do
        expect(described_class.match?("string", Brainpipe::Any)).to be true
        expect(described_class.match?(123, Brainpipe::Any)).to be true
        expect(described_class.match?(nil, Brainpipe::Any)).to be true
        expect(described_class.match?({}, Brainpipe::Any)).to be true
        expect(described_class.match?([], Brainpipe::Any)).to be true
      end
    end

    context "Optional type" do
      it "matches nil" do
        expect(described_class.match?(nil, Brainpipe::Optional[String])).to be true
      end

      it "matches the wrapped type" do
        expect(described_class.match?("hello", Brainpipe::Optional[String])).to be true
        expect(described_class.match?(123, Brainpipe::Optional[String])).to be false
      end
    end

    context "Enum type" do
      let(:status_enum) { Brainpipe::Enum[:pending, :active, :completed] }

      it "matches included values" do
        expect(described_class.match?(:pending, status_enum)).to be true
        expect(described_class.match?(:active, status_enum)).to be true
        expect(described_class.match?(:completed, status_enum)).to be true
      end

      it "rejects non-included values" do
        expect(described_class.match?(:invalid, status_enum)).to be false
        expect(described_class.match?("pending", status_enum)).to be false
      end
    end

    context "Union type" do
      let(:string_or_int) { Brainpipe::Union[String, Integer] }

      it "matches any of the types" do
        expect(described_class.match?("hello", string_or_int)).to be true
        expect(described_class.match?(123, string_or_int)).to be true
      end

      it "rejects other types" do
        expect(described_class.match?(3.14, string_or_int)).to be false
        expect(described_class.match?(:symbol, string_or_int)).to be false
      end
    end

    context "Array types" do
      it "matches arrays" do
        expect(described_class.match?([], Array)).to be true
        expect(described_class.match?([1, 2, 3], Array)).to be true
        expect(described_class.match?("not array", Array)).to be false
      end

      it "matches typed arrays" do
        expect(described_class.match?(["a", "b"], [String])).to be true
        expect(described_class.match?([1, 2], [Integer])).to be true
        expect(described_class.match?([], [String])).to be true
      end

      it "rejects arrays with wrong element types" do
        expect(described_class.match?([1, 2, 3], [String])).to be false
        expect(described_class.match?(["a", 1], [String])).to be false
      end
    end

    context "Hash with typed keys/values" do
      it "matches hashes with correct key/value types" do
        expect(described_class.match?({ "a" => 1, "b" => 2 }, { String => Integer })).to be true
        expect(described_class.match?({}, { String => Integer })).to be true
      end

      it "rejects hashes with wrong key types" do
        expect(described_class.match?({ a: 1 }, { String => Integer })).to be false
      end

      it "rejects hashes with wrong value types" do
        expect(described_class.match?({ "a" => "1" }, { String => Integer })).to be false
      end
    end

    context "Object structure" do
      let(:person_schema) { { name: String, age: Integer } }

      it "matches objects with correct structure" do
        expect(described_class.match?({ name: "Alice", age: 30 }, person_schema)).to be true
      end

      it "rejects objects with wrong property types" do
        expect(described_class.match?({ name: "Alice", age: "30" }, person_schema)).to be false
      end

      it "rejects objects with missing required properties" do
        expect(described_class.match?({ name: "Alice" }, person_schema)).to be false
      end

      it "allows extra properties" do
        expect(described_class.match?({ name: "Alice", age: 30, email: "a@b.com" }, person_schema)).to be true
      end
    end

    context "optional fields in structure" do
      let(:schema) { { name: String, "email?": String } }

      it "allows missing optional fields" do
        expect(described_class.match?({ name: "Alice" }, schema)).to be true
      end

      it "validates optional fields when present" do
        expect(described_class.match?({ name: "Alice", email: "a@b.com" }, schema)).to be true
        expect(described_class.match?({ name: "Alice", email: 123 }, schema)).to be false
      end
    end

    context "nested structures" do
      let(:schema) do
        {
          user: {
            name: String,
            address: {
              city: String,
              zip: String
            }
          },
          tags: [String]
        }
      end

      it "matches nested structures" do
        data = {
          user: {
            name: "Alice",
            address: { city: "NYC", zip: "10001" }
          },
          tags: ["admin", "active"]
        }
        expect(described_class.match?(data, schema)).to be true
      end

      it "rejects invalid nested structures" do
        data = {
          user: {
            name: "Alice",
            address: { city: "NYC", zip: 10001 }
          },
          tags: ["admin"]
        }
        expect(described_class.match?(data, schema)).to be false
      end
    end
  end

  describe ".validate!" do
    it "does not raise for valid values" do
      expect { described_class.validate!("hello", String) }.not_to raise_error
    end

    it "raises TypeMismatchError for invalid values" do
      expect { described_class.validate!(123, String) }
        .to raise_error(Brainpipe::TypeMismatchError)
    end

    context "error messages" do
      it "includes value description" do
        expect { described_class.validate!(123, String) }
          .to raise_error(/expected String, got Integer\(123\)/)
      end

      it "includes path when provided" do
        expect { described_class.validate!(123, String, path: "user.name") }
          .to raise_error(/user\.name: expected String/)
      end

      it "handles nil values" do
        expect { described_class.validate!(nil, String) }
          .to raise_error(/expected String, got nil/)
      end

      it "truncates long strings" do
        long_string = "x" * 100
        expect { described_class.validate!(long_string, Integer) }
          .to raise_error(/String\(100 chars\)/)
      end
    end
  end

  describe ".validate_structure!" do
    it "validates nested structures with paths" do
      schema = { user: { name: String } }
      data = { user: { name: 123 } }

      expect { described_class.validate_structure!(data, schema) }
        .to raise_error(Brainpipe::TypeMismatchError, /user\.name: expected String/)
    end

    it "validates arrays with indexed paths" do
      schema = [{ name: String }]
      data = [{ name: "Alice" }, { name: 123 }]

      expect { described_class.validate_structure!(data, schema) }
        .to raise_error(Brainpipe::TypeMismatchError, /\[1\]\.name: expected String/)
    end

    it "validates deeply nested array paths" do
      schema = { records: [{ tags: [String] }] }
      data = { records: [{ tags: ["a", "b"] }, { tags: ["c", 123] }] }

      expect { described_class.validate_structure!(data, schema) }
        .to raise_error(Brainpipe::TypeMismatchError, /records\[1\]\.tags\[1\]: expected String/)
    end

    it "reports missing required fields" do
      schema = { name: String, age: Integer }
      data = { name: "Alice" }

      expect { described_class.validate_structure!(data, schema) }
        .to raise_error(Brainpipe::TypeMismatchError, /age is required but missing/)
    end

    it "allows optional fields to be missing" do
      schema = { name: String, "email?": String }
      data = { name: "Alice" }

      expect { described_class.validate_structure!(data, schema) }.not_to raise_error
    end
  end
end

RSpec.describe Brainpipe::Types do
  describe "Any" do
    it "can be used with ===" do
      expect(Brainpipe::Any === "anything").to be true
      expect(Brainpipe::Any === nil).to be true
    end
  end

  describe "Boolean" do
    it "matches true and false" do
      expect(Brainpipe::Boolean === true).to be true
      expect(Brainpipe::Boolean === false).to be true
    end

    it "does not match other values" do
      expect(Brainpipe::Boolean === nil).to be false
      expect(Brainpipe::Boolean === "true").to be false
    end

    it "has readable inspect" do
      expect(Brainpipe::Boolean.inspect).to eq("Boolean")
    end
  end

  describe "Optional" do
    it "has readable inspect" do
      expect(Brainpipe::Optional[String].inspect).to eq("Optional[String]")
    end

    it "exposes the wrapped type" do
      opt = Brainpipe::Optional[Integer]
      expect(opt.type).to eq(Integer)
    end
  end

  describe "Enum" do
    it "has readable inspect" do
      enum = Brainpipe::Enum[:a, :b, :c]
      expect(enum.inspect).to eq("Enum[:a, :b, :c]")
    end

    it "exposes the values" do
      enum = Brainpipe::Enum[:a, :b]
      expect(enum.values).to eq([:a, :b])
    end
  end

  describe "Union" do
    it "has readable inspect" do
      union = Brainpipe::Union[String, Integer]
      expect(union.inspect).to eq("Union[String, Integer]")
    end

    it "exposes the types" do
      union = Brainpipe::Union[String, Symbol]
      expect(union.types).to eq([String, Symbol])
    end
  end
end
