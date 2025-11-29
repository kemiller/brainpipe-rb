RSpec.describe Brainpipe::Operations::Filter do
  describe "#initialize" do
    it "requires either 'condition' or 'field' option" do
      expect { described_class.new(options: {}) }
        .to raise_error(Brainpipe::ConfigurationError, /condition.*field/)
    end

    it "accepts field/value options" do
      filter = described_class.new(options: { field: :status, value: "active" })
      expect(filter).to be_a(described_class)
    end

    it "accepts condition proc" do
      filter = described_class.new(options: { condition: ->(ns) { ns[:count] > 0 } })
      expect(filter).to be_a(described_class)
    end
  end

  describe "#declared_reads" do
    it "reads the field when field option is provided" do
      filter = described_class.new(options: { field: :status, value: "active" })
      reads = filter.declared_reads

      expect(reads.keys).to eq([:status])
    end

    it "looks up type from prefix_schema" do
      filter = described_class.new(options: { field: :status, value: "active" })
      prefix_schema = { status: { type: String, optional: false } }
      reads = filter.declared_reads(prefix_schema)

      expect(reads[:status][:type]).to eq(String)
    end

    it "returns empty when using condition proc" do
      filter = described_class.new(options: { condition: ->(ns) { true } })
      expect(filter.declared_reads).to eq({})
    end
  end

  describe "#declared_sets" do
    it "returns empty (pure passthrough for schema)" do
      filter = described_class.new(options: { field: :status, value: "active" })
      expect(filter.declared_sets).to eq({})
    end
  end

  describe "#declared_deletes" do
    it "returns empty (pure passthrough for schema)" do
      filter = described_class.new(options: { field: :status, value: "active" })
      expect(filter.declared_deletes).to eq([])
    end
  end

  describe "#allows_count_change?" do
    it "returns true" do
      filter = described_class.new(options: { field: :status, value: "active" })
      expect(filter.allows_count_change?).to be true
    end
  end

  describe "#create" do
    context "with field/value matching" do
      it "filters namespaces matching field value" do
        filter = described_class.new(options: { field: :status, value: "active" })
        callable = filter.create
        namespaces = [
          Brainpipe::Namespace.new(status: "active", name: "one"),
          Brainpipe::Namespace.new(status: "inactive", name: "two"),
          Brainpipe::Namespace.new(status: "active", name: "three")
        ]

        result = callable.call(namespaces)

        expect(result.length).to eq(2)
        expect(result.map { |ns| ns[:name] }).to eq(["one", "three"])
      end

      it "returns empty array when no matches" do
        filter = described_class.new(options: { field: :status, value: "pending" })
        callable = filter.create
        namespaces = [
          Brainpipe::Namespace.new(status: "active"),
          Brainpipe::Namespace.new(status: "inactive")
        ]

        result = callable.call(namespaces)

        expect(result).to be_empty
      end

      it "returns all when all match" do
        filter = described_class.new(options: { field: :status, value: "active" })
        callable = filter.create
        namespaces = [
          Brainpipe::Namespace.new(status: "active"),
          Brainpipe::Namespace.new(status: "active")
        ]

        result = callable.call(namespaces)

        expect(result.length).to eq(2)
      end
    end

    context "with custom condition" do
      it "filters using the condition proc" do
        filter = described_class.new(options: { condition: ->(ns) { ns[:count] > 5 } })
        callable = filter.create
        namespaces = [
          Brainpipe::Namespace.new(count: 10, name: "high"),
          Brainpipe::Namespace.new(count: 3, name: "low"),
          Brainpipe::Namespace.new(count: 8, name: "medium")
        ]

        result = callable.call(namespaces)

        expect(result.length).to eq(2)
        expect(result.map { |ns| ns[:name] }).to eq(["high", "medium"])
      end

      it "preserves all fields in filtered namespaces" do
        filter = described_class.new(options: { condition: ->(ns) { ns[:keep] } })
        callable = filter.create
        namespaces = [
          Brainpipe::Namespace.new(keep: true, a: 1, b: 2, c: 3)
        ]

        result = callable.call(namespaces)

        expect(result[0][:a]).to eq(1)
        expect(result[0][:b]).to eq(2)
        expect(result[0][:c]).to eq(3)
      end
    end
  end
end
