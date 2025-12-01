# Link Operation Specification
#
# Link rewires namespace properties without changing namespace count.
# It supports four operations applied in order: copy → move → set → delete
#
# API:
#   Brainpipe::Operations::Link.new(
#     options: {
#       copy: { source: :target },      # copy field, keep source
#       move: { old_name: :new_name },  # move field, delete source
#       set: { constant: "value" },     # set constant values
#       delete: [:unwanted]             # delete fields
#     }
#   )
#
# Requirements: FR-13.1.1 through FR-13.1.7

RSpec.describe Brainpipe::Operations::Link do
  describe "#initialize" do
    it "requires at least one operation (copy, move, set, or delete)" do
      expect { described_class.new(options: {}) }
        .to raise_error(Brainpipe::ConfigurationError, /copy.*move.*set.*delete/i)
    end

    it "accepts copy option" do
      link = described_class.new(options: { copy: { a: :b } })
      expect(link).to be_a(described_class)
    end

    it "accepts move option" do
      link = described_class.new(options: { move: { a: :b } })
      expect(link).to be_a(described_class)
    end

    it "accepts set option" do
      link = described_class.new(options: { set: { a: "value" } })
      expect(link).to be_a(described_class)
    end

    it "accepts delete option" do
      link = described_class.new(options: { delete: [:a] })
      expect(link).to be_a(described_class)
    end

    it "accepts all options combined" do
      link = described_class.new(options: {
        copy: { a: :b },
        move: { c: :d },
        set: { e: "value" },
        delete: [:f]
      })
      expect(link).to be_a(described_class)
    end

    it "normalizes string keys to symbols" do
      link = described_class.new(options: { copy: { "source" => "target" } })
      expect(link).to be_a(described_class)
    end
  end

  describe "#declared_reads" do
    it "reads fields that are being copied" do
      link = described_class.new(options: { copy: { source: :target } })
      reads = link.declared_reads

      expect(reads.keys).to include(:source)
    end

    it "reads fields that are being moved" do
      link = described_class.new(options: { move: { source: :target } })
      reads = link.declared_reads

      expect(reads.keys).to include(:source)
    end

    it "does not read fields that are only being set or deleted" do
      link = described_class.new(options: { set: { a: 1 }, delete: [:b] })
      reads = link.declared_reads

      expect(reads.keys).not_to include(:a)
      expect(reads.keys).not_to include(:b)
    end

    it "looks up type from prefix_schema for copied fields" do
      link = described_class.new(options: { copy: { source: :target } })
      prefix_schema = { source: { type: String, optional: false } }
      reads = link.declared_reads(prefix_schema)

      expect(reads[:source][:type]).to eq(String)
    end

    it "looks up type from prefix_schema for moved fields" do
      link = described_class.new(options: { move: { source: :target } })
      prefix_schema = { source: { type: Integer, optional: false } }
      reads = link.declared_reads(prefix_schema)

      expect(reads[:source][:type]).to eq(Integer)
    end
  end

  describe "#declared_sets" do
    it "sets target fields from copy operations" do
      link = described_class.new(options: { copy: { source: :target } })
      sets = link.declared_sets

      expect(sets.keys).to include(:target)
    end

    it "sets target fields from move operations" do
      link = described_class.new(options: { move: { source: :target } })
      sets = link.declared_sets

      expect(sets.keys).to include(:target)
    end

    it "sets constant fields" do
      link = described_class.new(options: { set: { status: "done" } })
      sets = link.declared_sets

      expect(sets.keys).to include(:status)
    end

    it "preserves type from source for copied fields" do
      link = described_class.new(options: { copy: { source: :target } })
      prefix_schema = { source: { type: String, optional: false } }
      sets = link.declared_sets(prefix_schema)

      expect(sets[:target][:type]).to eq(String)
    end

    it "preserves type from source for moved fields" do
      link = described_class.new(options: { move: { source: :target } })
      prefix_schema = { source: { type: Integer, optional: false } }
      sets = link.declared_sets(prefix_schema)

      expect(sets[:target][:type]).to eq(Integer)
    end

    it "infers type from value for set operations" do
      link = described_class.new(options: { set: { count: 42 } })
      sets = link.declared_sets

      expect(sets[:count][:type]).to eq(Integer)
    end
  end

  describe "#declared_deletes" do
    it "deletes explicitly specified fields" do
      link = described_class.new(options: { delete: [:unwanted, :temporary] })
      deletes = link.declared_deletes

      expect(deletes).to include(:unwanted, :temporary)
    end

    it "deletes source fields from move operations" do
      link = described_class.new(options: { move: { source: :target } })
      deletes = link.declared_deletes

      expect(deletes).to include(:source)
    end

    it "does NOT delete source fields from copy operations" do
      link = described_class.new(options: { copy: { source: :target } })
      deletes = link.declared_deletes

      expect(deletes).not_to include(:source)
    end
  end

  describe "#allows_count_change?" do
    it "returns false (Link maintains 1:1 namespace count)" do
      link = described_class.new(options: { copy: { a: :b } })
      expect(link.allows_count_change?).to be false
    end
  end

  describe "#create" do
    describe "copy operations" do
      it "copies a field while preserving the source" do
        link = described_class.new(options: { copy: { source: :target } })
        callable = link.create
        namespaces = [Brainpipe::Namespace.new(source: "value")]

        result = callable.call(namespaces)

        expect(result[0][:source]).to eq("value")
        expect(result[0][:target]).to eq("value")
      end

      it "copies multiple fields" do
        link = described_class.new(options: { copy: { a: :x, b: :y } })
        callable = link.create
        namespaces = [Brainpipe::Namespace.new(a: 1, b: 2)]

        result = callable.call(namespaces)

        expect(result[0][:a]).to eq(1)
        expect(result[0][:b]).to eq(2)
        expect(result[0][:x]).to eq(1)
        expect(result[0][:y]).to eq(2)
      end
    end

    describe "move operations" do
      it "moves a field (deletes source)" do
        link = described_class.new(options: { move: { source: :target } })
        callable = link.create
        namespaces = [Brainpipe::Namespace.new(source: "value")]

        result = callable.call(namespaces)

        expect(result[0].key?(:source)).to be false
        expect(result[0][:target]).to eq("value")
      end

      it "moves multiple fields" do
        link = described_class.new(options: { move: { a: :x, b: :y } })
        callable = link.create
        namespaces = [Brainpipe::Namespace.new(a: 1, b: 2)]

        result = callable.call(namespaces)

        expect(result[0].key?(:a)).to be false
        expect(result[0].key?(:b)).to be false
        expect(result[0][:x]).to eq(1)
        expect(result[0][:y]).to eq(2)
      end
    end

    describe "set operations" do
      it "sets constant values" do
        link = described_class.new(options: { set: { status: "done", count: 0 } })
        callable = link.create
        namespaces = [Brainpipe::Namespace.new(other: "preserved")]

        result = callable.call(namespaces)

        expect(result[0][:status]).to eq("done")
        expect(result[0][:count]).to eq(0)
        expect(result[0][:other]).to eq("preserved")
      end

      it "overwrites existing fields with constants" do
        link = described_class.new(options: { set: { status: "done" } })
        callable = link.create
        namespaces = [Brainpipe::Namespace.new(status: "pending")]

        result = callable.call(namespaces)

        expect(result[0][:status]).to eq("done")
      end
    end

    describe "delete operations" do
      it "deletes specified fields" do
        link = described_class.new(options: { delete: [:temp, :unwanted] })
        callable = link.create
        namespaces = [Brainpipe::Namespace.new(temp: 1, unwanted: 2, keep: 3)]

        result = callable.call(namespaces)

        expect(result[0].key?(:temp)).to be false
        expect(result[0].key?(:unwanted)).to be false
        expect(result[0][:keep]).to eq(3)
      end
    end

    describe "operation ordering" do
      it "applies operations in order: copy → move → set → delete" do
        # This tests that:
        # 1. copy happens first (so we can copy a field before moving it)
        # 2. move happens second
        # 3. set happens third
        # 4. delete happens last (so we can delete fields set by earlier ops)
        link = described_class.new(options: {
          copy: { original: :backup },
          move: { original: :renamed },
          set: { status: "processed" },
          delete: [:backup]
        })
        callable = link.create
        namespaces = [Brainpipe::Namespace.new(original: "value")]

        result = callable.call(namespaces)

        expect(result[0].key?(:original)).to be false  # moved away
        expect(result[0][:renamed]).to eq("value")     # move target
        expect(result[0].key?(:backup)).to be false    # deleted after copy
        expect(result[0][:status]).to eq("processed")  # set
      end
    end

    describe "multiple namespaces" do
      it "processes each namespace independently" do
        link = described_class.new(options: { copy: { input: :output } })
        callable = link.create
        namespaces = [
          Brainpipe::Namespace.new(input: "one"),
          Brainpipe::Namespace.new(input: "two"),
          Brainpipe::Namespace.new(input: "three")
        ]

        result = callable.call(namespaces)

        expect(result.length).to eq(3)
        expect(result[0][:output]).to eq("one")
        expect(result[1][:output]).to eq("two")
        expect(result[2][:output]).to eq("three")
      end
    end

    describe "preserving other fields" do
      it "preserves fields not involved in any operation" do
        link = described_class.new(options: { copy: { a: :b } })
        callable = link.create
        namespaces = [Brainpipe::Namespace.new(a: 1, unrelated: "preserved", another: 42)]

        result = callable.call(namespaces)

        expect(result[0][:unrelated]).to eq("preserved")
        expect(result[0][:another]).to eq(42)
      end
    end
  end
end
