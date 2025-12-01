# Explode Operation Specification
#
# Explode fans out array fields from 1 namespace into N namespaces.
# It also includes all Link capabilities (copy, move, set, delete) applied after splitting.
#
# API:
#   Brainpipe::Operations::Explode.new(
#     options: {
#       split: {
#         results: :result,   # array field → individual elements with new name
#         images: :image      # must match cardinality of other split fields
#       },
#       on_empty: :skip,      # :skip (default) or :error
#       copy: { ... },        # Link: copy fields
#       move: { ... },        # Link: move fields
#       set: { ... },         # Link: set constants
#       delete: [...]         # Link: delete fields
#     }
#   )
#
# Behavior:
#   - Fields in `split:` are array fields fanned out (one element per output namespace)
#   - Multiple split fields must have the same array length (validated at runtime)
#   - All other fields are implicitly copied to each output namespace
#   - Link operations (copy, move, set, delete) are applied after splitting
#   - `on_empty: :skip` returns 0 namespaces for empty arrays (default)
#   - `on_empty: :error` raises ExecutionError for empty arrays
#
# Requirements: FR-13.3.1 through FR-13.3.7

RSpec.describe Brainpipe::Operations::Explode do
  describe "#initialize" do
    it "requires split option" do
      expect { described_class.new(options: {}) }
        .to raise_error(Brainpipe::ConfigurationError, /split/i)
    end

    it "accepts split option" do
      explode = described_class.new(options: { split: { results: :result } })
      expect(explode).to be_a(described_class)
    end

    it "accepts on_empty option" do
      explode = described_class.new(options: { split: { results: :result }, on_empty: :error })
      expect(explode).to be_a(described_class)
    end

    it "defaults on_empty to :skip" do
      explode = described_class.new(options: { split: { results: :result } })
      expect(explode).to be_a(described_class)
    end

    it "raises error for invalid on_empty value" do
      expect { described_class.new(options: { split: { results: :result }, on_empty: :invalid }) }
        .to raise_error(Brainpipe::ConfigurationError, /on_empty/i)
    end

    it "accepts Link options (copy, move, set, delete)" do
      explode = described_class.new(options: {
        split: { results: :result },
        copy: { a: :b },
        move: { c: :d },
        set: { e: "value" },
        delete: [:f]
      })
      expect(explode).to be_a(described_class)
    end

    it "normalizes string keys to symbols" do
      explode = described_class.new(options: { split: { "results" => "result" } })
      expect(explode).to be_a(described_class)
    end
  end

  describe "#allows_count_change?" do
    it "returns true (Explode fans out 1 namespace into N)" do
      explode = described_class.new(options: { split: { results: :result } })
      expect(explode.allows_count_change?).to be true
    end
  end

  describe "#declared_reads" do
    it "reads the split source fields" do
      explode = described_class.new(options: { split: { results: :result, images: :image } })
      reads = explode.declared_reads

      expect(reads.keys).to include(:results, :images)
    end

    it "looks up type from prefix_schema" do
      explode = described_class.new(options: { split: { results: :result } })
      prefix_schema = { results: { type: [String], optional: false } }
      reads = explode.declared_reads(prefix_schema)

      expect(reads[:results][:type]).to eq([String])
    end
  end

  describe "#declared_sets" do
    it "sets the split target fields with element type" do
      explode = described_class.new(options: { split: { results: :result } })
      prefix_schema = { results: { type: [String], optional: false } }
      sets = explode.declared_sets(prefix_schema)

      expect(sets[:result][:type]).to eq(String)
    end

    it "includes copied fields (non-split fields are implicitly copied)" do
      explode = described_class.new(options: { split: { results: :result } })
      prefix_schema = {
        results: { type: [String], optional: false },
        name: { type: String, optional: false }
      }
      sets = explode.declared_sets(prefix_schema)

      expect(sets.keys).to include(:name)
      expect(sets[:name][:type]).to eq(String)
    end

    it "does not include split source fields in output" do
      explode = described_class.new(options: { split: { results: :result } })
      prefix_schema = { results: { type: [String], optional: false } }
      sets = explode.declared_sets(prefix_schema)

      expect(sets.keys).not_to include(:results)
    end

    it "includes Link set operations" do
      explode = described_class.new(options: { split: { results: :result }, set: { exploded: true } })
      sets = explode.declared_sets({})

      expect(sets[:exploded][:type]).to eq(TrueClass)
    end
  end

  describe "#declared_deletes" do
    it "includes split source fields (they become individual elements)" do
      explode = described_class.new(options: { split: { results: :result } })
      deletes = explode.declared_deletes

      expect(deletes).to include(:results)
    end

    it "includes explicit delete fields" do
      explode = described_class.new(options: { split: { results: :result }, delete: [:temp] })
      deletes = explode.declared_deletes

      expect(deletes).to include(:temp)
    end

    it "includes move source fields" do
      explode = described_class.new(options: { split: { results: :result }, move: { old: :new } })
      deletes = explode.declared_deletes

      expect(deletes).to include(:old)
    end
  end

  describe "#create" do
    describe "splitting single array field" do
      it "creates one namespace per array element" do
        explode = described_class.new(options: { split: { results: :result } })
        callable = explode.create
        namespaces = [Brainpipe::Namespace.new(results: ["a", "b", "c"])]

        result = callable.call(namespaces)

        expect(result.length).to eq(3)
        expect(result[0][:result]).to eq("a")
        expect(result[1][:result]).to eq("b")
        expect(result[2][:result]).to eq("c")
      end

      it "removes the source array field" do
        explode = described_class.new(options: { split: { results: :result } })
        callable = explode.create
        namespaces = [Brainpipe::Namespace.new(results: ["a", "b"])]

        result = callable.call(namespaces)

        expect(result[0].key?(:results)).to be false
        expect(result[1].key?(:results)).to be false
      end
    end

    describe "splitting multiple array fields" do
      it "splits multiple fields with same cardinality" do
        explode = described_class.new(options: { split: { results: :result, images: :image } })
        callable = explode.create
        namespaces = [Brainpipe::Namespace.new(
          results: ["r1", "r2", "r3"],
          images: ["i1", "i2", "i3"]
        )]

        result = callable.call(namespaces)

        expect(result.length).to eq(3)
        expect(result[0][:result]).to eq("r1")
        expect(result[0][:image]).to eq("i1")
        expect(result[1][:result]).to eq("r2")
        expect(result[1][:image]).to eq("i2")
        expect(result[2][:result]).to eq("r3")
        expect(result[2][:image]).to eq("i3")
      end

      it "raises error when split fields have different cardinalities" do
        explode = described_class.new(options: { split: { results: :result, images: :image } })
        callable = explode.create
        namespaces = [Brainpipe::Namespace.new(
          results: ["r1", "r2", "r3"],
          images: ["i1", "i2"]  # different length!
        )]

        expect { callable.call(namespaces) }
          .to raise_error(Brainpipe::ExecutionError, /cardinality|cardinalities/i)
      end
    end

    describe "copying non-split fields" do
      it "copies non-split fields to all output namespaces" do
        explode = described_class.new(options: { split: { results: :result } })
        callable = explode.create
        namespaces = [Brainpipe::Namespace.new(
          results: ["a", "b"],
          name: "shared",
          count: 42
        )]

        result = callable.call(namespaces)

        expect(result[0][:name]).to eq("shared")
        expect(result[0][:count]).to eq(42)
        expect(result[1][:name]).to eq("shared")
        expect(result[1][:count]).to eq(42)
      end
    end

    describe "empty array handling" do
      context "with on_empty: :skip (default)" do
        it "returns empty array for empty split field" do
          explode = described_class.new(options: { split: { results: :result }, on_empty: :skip })
          callable = explode.create
          namespaces = [Brainpipe::Namespace.new(results: [])]

          result = callable.call(namespaces)

          expect(result).to be_empty
        end

        it "returns empty array when all split fields are empty" do
          explode = described_class.new(options: { split: { results: :result, images: :image }, on_empty: :skip })
          callable = explode.create
          namespaces = [Brainpipe::Namespace.new(results: [], images: [])]

          result = callable.call(namespaces)

          expect(result).to be_empty
        end
      end

      context "with on_empty: :error" do
        it "raises error for empty split field" do
          explode = described_class.new(options: { split: { results: :result }, on_empty: :error })
          callable = explode.create
          namespaces = [Brainpipe::Namespace.new(results: [])]

          expect { callable.call(namespaces) }
            .to raise_error(Brainpipe::ExecutionError, /empty/i)
        end
      end
    end

    describe "Link operations after split" do
      it "applies copy after splitting" do
        explode = described_class.new(options: {
          split: { results: :result },
          copy: { result: :backup }
        })
        callable = explode.create
        namespaces = [Brainpipe::Namespace.new(results: ["a", "b"])]

        result = callable.call(namespaces)

        expect(result[0][:result]).to eq("a")
        expect(result[0][:backup]).to eq("a")
        expect(result[1][:result]).to eq("b")
        expect(result[1][:backup]).to eq("b")
      end

      it "applies move after splitting" do
        explode = described_class.new(options: {
          split: { results: :result },
          move: { result: :renamed }
        })
        callable = explode.create
        namespaces = [Brainpipe::Namespace.new(results: ["a", "b"])]

        result = callable.call(namespaces)

        expect(result[0].key?(:result)).to be false
        expect(result[0][:renamed]).to eq("a")
        expect(result[1].key?(:result)).to be false
        expect(result[1][:renamed]).to eq("b")
      end

      it "applies set after splitting" do
        explode = described_class.new(options: {
          split: { results: :result },
          set: { exploded: true }
        })
        callable = explode.create
        namespaces = [Brainpipe::Namespace.new(results: ["a", "b"])]

        result = callable.call(namespaces)

        expect(result[0][:exploded]).to be true
        expect(result[1][:exploded]).to be true
      end

      it "applies delete after splitting" do
        explode = described_class.new(options: {
          split: { results: :result },
          delete: [:temp]
        })
        callable = explode.create
        namespaces = [Brainpipe::Namespace.new(results: ["a", "b"], temp: "remove me")]

        result = callable.call(namespaces)

        expect(result[0].key?(:temp)).to be false
        expect(result[1].key?(:temp)).to be false
      end
    end

    describe "multiple input namespaces" do
      it "explodes each input namespace independently" do
        explode = described_class.new(options: { split: { results: :result } })
        callable = explode.create
        namespaces = [
          Brainpipe::Namespace.new(results: ["a", "b"], batch: 1),
          Brainpipe::Namespace.new(results: ["x", "y", "z"], batch: 2)
        ]

        result = callable.call(namespaces)

        expect(result.length).to eq(5)  # 2 from first + 3 from second
        expect(result[0][:result]).to eq("a")
        expect(result[0][:batch]).to eq(1)
        expect(result[1][:result]).to eq("b")
        expect(result[1][:batch]).to eq(1)
        expect(result[2][:result]).to eq("x")
        expect(result[2][:batch]).to eq(2)
        expect(result[3][:result]).to eq("y")
        expect(result[3][:batch]).to eq(2)
        expect(result[4][:result]).to eq("z")
        expect(result[4][:batch]).to eq(2)
      end

      it "handles mixed empty and non-empty arrays across namespaces" do
        explode = described_class.new(options: { split: { results: :result }, on_empty: :skip })
        callable = explode.create
        namespaces = [
          Brainpipe::Namespace.new(results: ["a"], batch: 1),
          Brainpipe::Namespace.new(results: [], batch: 2),  # empty - skipped
          Brainpipe::Namespace.new(results: ["b", "c"], batch: 3)
        ]

        result = callable.call(namespaces)

        expect(result.length).to eq(3)  # 1 + 0 + 2
        expect(result.map { |ns| ns[:batch] }).to eq([1, 3, 3])
      end
    end

    describe "preserving complex values" do
      it "preserves complex objects in split fields" do
        explode = described_class.new(options: { split: { items: :item } })
        callable = explode.create
        namespaces = [Brainpipe::Namespace.new(items: [
          { id: 1, name: "first" },
          { id: 2, name: "second" }
        ])]

        result = callable.call(namespaces)

        expect(result[0][:item]).to eq({ id: 1, name: "first" })
        expect(result[1][:item]).to eq({ id: 2, name: "second" })
      end

      it "preserves complex objects in copied fields" do
        explode = described_class.new(options: { split: { results: :result } })
        callable = explode.create
        namespaces = [Brainpipe::Namespace.new(
          results: ["a", "b"],
          config: { nested: { deep: "value" } }
        )]

        result = callable.call(namespaces)

        expect(result[0][:config]).to eq({ nested: { deep: "value" } })
        expect(result[1][:config]).to eq({ nested: { deep: "value" } })
      end
    end

    describe "single element array" do
      it "creates single namespace from single-element array" do
        explode = described_class.new(options: { split: { results: :result } })
        callable = explode.create
        namespaces = [Brainpipe::Namespace.new(results: ["only"])]

        result = callable.call(namespaces)

        expect(result.length).to eq(1)
        expect(result[0][:result]).to eq("only")
      end
    end
  end
end
