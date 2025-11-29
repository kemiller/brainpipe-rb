RSpec.describe Brainpipe::Operations::Transform do
  describe "#initialize" do
    it "requires 'from' option" do
      expect { described_class.new(options: { to: :output }) }
        .to raise_error(Brainpipe::ConfigurationError, /from/)
    end

    it "requires 'to' option" do
      expect { described_class.new(options: { from: :input }) }
        .to raise_error(Brainpipe::ConfigurationError, /to/)
    end

    it "accepts valid options" do
      transform = described_class.new(options: { from: :input, to: :output })
      expect(transform).to be_a(described_class)
    end

    it "defaults delete_source to false" do
      transform = described_class.new(options: { from: :input, to: :output })
      expect(transform.declared_deletes).to be_empty
    end

    it "accepts delete_source option" do
      transform = described_class.new(options: { from: :input, to: :output, delete_source: true })
      expect(transform.declared_deletes).to eq([:input])
    end
  end

  describe "#declared_reads" do
    it "reads the source field" do
      transform = described_class.new(options: { from: :input, to: :output })
      reads = transform.declared_reads

      expect(reads.keys).to eq([:input])
    end

    it "looks up type from prefix_schema" do
      transform = described_class.new(options: { from: :input, to: :output })
      prefix_schema = { input: { type: String, optional: false } }
      reads = transform.declared_reads(prefix_schema)

      expect(reads[:input][:type]).to eq(String)
    end
  end

  describe "#declared_sets" do
    it "sets the target field" do
      transform = described_class.new(options: { from: :input, to: :output })
      sets = transform.declared_sets

      expect(sets.keys).to eq([:output])
    end

    it "preserves type from source field" do
      transform = described_class.new(options: { from: :input, to: :output })
      prefix_schema = { input: { type: Integer, optional: false } }
      sets = transform.declared_sets(prefix_schema)

      expect(sets[:output][:type]).to eq(Integer)
    end
  end

  describe "#declared_deletes" do
    it "returns empty when delete_source is false" do
      transform = described_class.new(options: { from: :input, to: :output })
      expect(transform.declared_deletes).to eq([])
    end

    it "returns source field when delete_source is true" do
      transform = described_class.new(options: { from: :input, to: :output, delete_source: true })
      expect(transform.declared_deletes).to eq([:input])
    end
  end

  describe "#create" do
    it "renames a field (copy)" do
      transform = described_class.new(options: { from: :input, to: :output })
      callable = transform.create
      namespaces = [Brainpipe::Namespace.new(input: "hello")]

      result = callable.call(namespaces)

      expect(result[0][:input]).to eq("hello")
      expect(result[0][:output]).to eq("hello")
    end

    it "renames a field (move when delete_source is true)" do
      transform = described_class.new(options: { from: :input, to: :output, delete_source: true })
      callable = transform.create
      namespaces = [Brainpipe::Namespace.new(input: "hello")]

      result = callable.call(namespaces)

      expect(result[0][:output]).to eq("hello")
      expect(result[0].key?(:input)).to be false
    end

    it "preserves other fields" do
      transform = described_class.new(options: { from: :input, to: :output })
      callable = transform.create
      namespaces = [Brainpipe::Namespace.new(input: "hello", other: "preserved")]

      result = callable.call(namespaces)

      expect(result[0][:other]).to eq("preserved")
    end

    it "handles multiple namespaces" do
      transform = described_class.new(options: { from: :input, to: :output })
      callable = transform.create
      namespaces = [
        Brainpipe::Namespace.new(input: "one"),
        Brainpipe::Namespace.new(input: "two"),
        Brainpipe::Namespace.new(input: "three")
      ]

      result = callable.call(namespaces)

      expect(result.map { |ns| ns[:output] }).to eq(["one", "two", "three"])
    end
  end
end
