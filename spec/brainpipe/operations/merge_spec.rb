RSpec.describe Brainpipe::Operations::Merge do
  describe "#initialize" do
    it "requires 'sources' option" do
      expect { described_class.new(options: { target: :combined, target_type: String }) }
        .to raise_error(Brainpipe::ConfigurationError, /sources/)
    end

    it "requires 'target' option" do
      expect { described_class.new(options: { sources: [:a, :b], target_type: String }) }
        .to raise_error(Brainpipe::ConfigurationError, /target/)
    end

    it "requires 'target_type' option" do
      expect { described_class.new(options: { sources: [:a, :b], target: :combined }) }
        .to raise_error(Brainpipe::ConfigurationError, /target_type/)
    end

    it "accepts valid options" do
      merge = described_class.new(options: { sources: [:a, :b], target: :combined, target_type: String })
      expect(merge).to be_a(described_class)
    end

    it "defaults delete_sources to false" do
      merge = described_class.new(options: { sources: [:a, :b], target: :combined, target_type: String })
      expect(merge.declared_deletes).to be_empty
    end

    it "accepts delete_sources option" do
      merge = described_class.new(options: { sources: [:a, :b], target: :combined, target_type: String, delete_sources: true })
      expect(merge.declared_deletes).to eq([:a, :b])
    end
  end

  describe "#declared_reads" do
    it "reads all source fields" do
      merge = described_class.new(options: { sources: [:a, :b, :c], target: :combined, target_type: String })
      reads = merge.declared_reads

      expect(reads.keys).to eq([:a, :b, :c])
    end

    it "looks up types from prefix_schema" do
      merge = described_class.new(options: { sources: [:a, :b], target: :combined, target_type: String })
      prefix_schema = {
        a: { type: Integer, optional: false },
        b: { type: Float, optional: false }
      }
      reads = merge.declared_reads(prefix_schema)

      expect(reads[:a][:type]).to eq(Integer)
      expect(reads[:b][:type]).to eq(Float)
    end
  end

  describe "#declared_sets" do
    it "sets the target field with explicit type" do
      merge = described_class.new(options: { sources: [:a, :b], target: :combined, target_type: String })
      sets = merge.declared_sets

      expect(sets.keys).to eq([:combined])
      expect(sets[:combined][:type]).to eq(String)
    end
  end

  describe "#declared_deletes" do
    it "returns empty when delete_sources is false" do
      merge = described_class.new(options: { sources: [:a, :b], target: :combined, target_type: String })
      expect(merge.declared_deletes).to eq([])
    end

    it "returns all source fields when delete_sources is true" do
      merge = described_class.new(options: { sources: [:a, :b], target: :combined, target_type: String, delete_sources: true })
      expect(merge.declared_deletes).to eq([:a, :b])
    end
  end

  describe "#create" do
    it "combines fields using default combiner (join with space)" do
      merge = described_class.new(options: { sources: [:first, :last], target: :full_name, target_type: String })
      callable = merge.create
      namespaces = [Brainpipe::Namespace.new(first: "John", last: "Doe")]

      result = callable.call(namespaces)

      expect(result[0][:full_name]).to eq("John Doe")
    end

    it "uses custom combiner proc" do
      combiner = ->(values) { values.sum }
      merge = described_class.new(options: { sources: [:a, :b, :c], target: :total, target_type: Integer, combiner: combiner })
      callable = merge.create
      namespaces = [Brainpipe::Namespace.new(a: 1, b: 2, c: 3)]

      result = callable.call(namespaces)

      expect(result[0][:total]).to eq(6)
    end

    it "preserves source fields when delete_sources is false" do
      merge = described_class.new(options: { sources: [:a, :b], target: :combined, target_type: String })
      callable = merge.create
      namespaces = [Brainpipe::Namespace.new(a: "x", b: "y")]

      result = callable.call(namespaces)

      expect(result[0][:a]).to eq("x")
      expect(result[0][:b]).to eq("y")
      expect(result[0][:combined]).to eq("x y")
    end

    it "removes source fields when delete_sources is true" do
      merge = described_class.new(options: { sources: [:a, :b], target: :combined, target_type: String, delete_sources: true })
      callable = merge.create
      namespaces = [Brainpipe::Namespace.new(a: "x", b: "y")]

      result = callable.call(namespaces)

      expect(result[0].key?(:a)).to be false
      expect(result[0].key?(:b)).to be false
      expect(result[0][:combined]).to eq("x y")
    end

    it "handles multiple namespaces" do
      combiner = ->(values) { values.join("-") }
      merge = described_class.new(options: { sources: [:a, :b], target: :combined, target_type: String, combiner: combiner })
      callable = merge.create
      namespaces = [
        Brainpipe::Namespace.new(a: "1", b: "2"),
        Brainpipe::Namespace.new(a: "3", b: "4")
      ]

      result = callable.call(namespaces)

      expect(result[0][:combined]).to eq("1-2")
      expect(result[1][:combined]).to eq("3-4")
    end

    it "preserves other fields" do
      merge = described_class.new(options: { sources: [:a, :b], target: :combined, target_type: String })
      callable = merge.create
      namespaces = [Brainpipe::Namespace.new(a: "x", b: "y", other: "preserved")]

      result = callable.call(namespaces)

      expect(result[0][:other]).to eq("preserved")
    end
  end
end
