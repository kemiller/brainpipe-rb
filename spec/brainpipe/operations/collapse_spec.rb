# Collapse Operation Specification
#
# Collapse merges N namespaces into 1 with configurable per-field merge strategies.
# It also includes all Link capabilities (copy, move, set, delete) applied after merging.
#
# API:
#   Brainpipe::Operations::Collapse.new(
#     options: {
#       merge: {
#         items: :collect,    # gather all values into array
#         total: :sum,        # add numeric values
#         text: :concat,      # concatenate strings/arrays
#         name: :first,       # take first value
#         type: :equal,       # all must match (DEFAULT)
#         ids: :distinct      # all must be unique
#       },
#       copy: { ... },        # Link: copy fields
#       move: { ... },        # Link: move fields
#       set: { ... },         # Link: set constants
#       delete: [...]         # Link: delete fields
#     }
#   )
#
# Merge Strategies:
#   :collect  - gather all values into an array
#   :sum      - add numeric values together
#   :concat   - concatenate strings or arrays
#   :first    - take the first value
#   :last     - take the last value
#   :equal    - all values must be equal, error otherwise (DEFAULT)
#   :distinct - all values must be unique, error on duplicates
#
# Requirements: FR-13.2.1 through FR-13.2.7

RSpec.describe Brainpipe::Operations::Collapse do
  describe "#initialize" do
    it "accepts empty options (uses default :equal strategy for all fields)" do
      collapse = described_class.new(options: {})
      expect(collapse).to be_a(described_class)
    end

    it "accepts merge strategies" do
      collapse = described_class.new(options: { merge: { items: :collect } })
      expect(collapse).to be_a(described_class)
    end

    it "accepts Link options (copy, move, set, delete)" do
      collapse = described_class.new(options: {
        merge: { items: :collect },
        copy: { a: :b },
        move: { c: :d },
        set: { e: "value" },
        delete: [:f]
      })
      expect(collapse).to be_a(described_class)
    end

    it "raises error for unknown merge strategy" do
      expect { described_class.new(options: { merge: { field: :unknown_strategy } }) }
        .to raise_error(Brainpipe::ConfigurationError, /unknown.*strategy/i)
    end

    it "normalizes string keys to symbols" do
      collapse = described_class.new(options: { merge: { "field" => "collect" } })
      expect(collapse).to be_a(described_class)
    end
  end

  describe "#allows_count_change?" do
    it "returns true (Collapse merges N namespaces into 1)" do
      collapse = described_class.new(options: {})
      expect(collapse.allows_count_change?).to be true
    end
  end

  describe "#declared_reads" do
    it "reads all fields from prefix_schema (we're collapsing everything)" do
      collapse = described_class.new(options: {})
      prefix_schema = {
        a: { type: String, optional: false },
        b: { type: Integer, optional: false }
      }
      reads = collapse.declared_reads(prefix_schema)

      expect(reads.keys).to include(:a, :b)
    end
  end

  describe "#declared_sets" do
    it "sets all fields from prefix_schema after collapse" do
      collapse = described_class.new(options: {})
      prefix_schema = {
        a: { type: String, optional: false },
        b: { type: Integer, optional: false }
      }
      sets = collapse.declared_sets(prefix_schema)

      expect(sets.keys).to include(:a, :b)
    end

    it "changes type to array for :collect strategy" do
      collapse = described_class.new(options: { merge: { items: :collect } })
      prefix_schema = { items: { type: String, optional: false } }
      sets = collapse.declared_sets(prefix_schema)

      expect(sets[:items][:type]).to eq([String])
    end

    it "changes type to array for :distinct strategy" do
      collapse = described_class.new(options: { merge: { ids: :distinct } })
      prefix_schema = { ids: { type: Integer, optional: false } }
      sets = collapse.declared_sets(prefix_schema)

      expect(sets[:ids][:type]).to eq([Integer])
    end

    it "preserves type for other strategies" do
      collapse = described_class.new(options: { merge: { total: :sum } })
      prefix_schema = { total: { type: Integer, optional: false } }
      sets = collapse.declared_sets(prefix_schema)

      expect(sets[:total][:type]).to eq(Integer)
    end

    it "includes Link set operations" do
      collapse = described_class.new(options: { set: { status: "collapsed" } })
      sets = collapse.declared_sets({})

      expect(sets[:status][:type]).to eq(String)
    end

    it "includes Link move target fields" do
      collapse = described_class.new(options: { move: { old: :new } })
      prefix_schema = { old: { type: String, optional: false } }
      sets = collapse.declared_sets(prefix_schema)

      expect(sets.keys).to include(:new)
    end
  end

  describe "#declared_deletes" do
    it "includes explicit delete fields" do
      collapse = described_class.new(options: { delete: [:temp] })
      deletes = collapse.declared_deletes

      expect(deletes).to include(:temp)
    end

    it "includes move source fields" do
      collapse = described_class.new(options: { move: { old: :new } })
      deletes = collapse.declared_deletes

      expect(deletes).to include(:old)
    end
  end

  describe "#create" do
    describe ":collect strategy" do
      it "gathers all values into an array" do
        collapse = described_class.new(options: { merge: { items: :collect } })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(items: "a"),
          Brainpipe::Namespace.new(items: "b"),
          Brainpipe::Namespace.new(items: "c")
        ]

        result = callable.call(namespaces)

        expect(result.length).to eq(1)
        expect(result[0][:items]).to eq(["a", "b", "c"])
      end

      it "preserves order of values" do
        collapse = described_class.new(options: { merge: { items: :collect } })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(items: 3),
          Brainpipe::Namespace.new(items: 1),
          Brainpipe::Namespace.new(items: 2)
        ]

        result = callable.call(namespaces)

        expect(result[0][:items]).to eq([3, 1, 2])
      end
    end

    describe ":sum strategy" do
      it "adds numeric values together" do
        collapse = described_class.new(options: { merge: { total: :sum } })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(total: 10),
          Brainpipe::Namespace.new(total: 20),
          Brainpipe::Namespace.new(total: 30)
        ]

        result = callable.call(namespaces)

        expect(result[0][:total]).to eq(60)
      end

      it "handles floats" do
        collapse = described_class.new(options: { merge: { score: :sum } })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(score: 1.5),
          Brainpipe::Namespace.new(score: 2.5)
        ]

        result = callable.call(namespaces)

        expect(result[0][:score]).to eq(4.0)
      end
    end

    describe ":concat strategy" do
      it "concatenates strings" do
        collapse = described_class.new(options: { merge: { text: :concat } })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(text: "Hello"),
          Brainpipe::Namespace.new(text: " "),
          Brainpipe::Namespace.new(text: "World")
        ]

        result = callable.call(namespaces)

        expect(result[0][:text]).to eq("Hello World")
      end

      it "concatenates arrays" do
        collapse = described_class.new(options: { merge: { tags: :concat } })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(tags: ["a", "b"]),
          Brainpipe::Namespace.new(tags: ["c"]),
          Brainpipe::Namespace.new(tags: ["d", "e"])
        ]

        result = callable.call(namespaces)

        expect(result[0][:tags]).to eq(["a", "b", "c", "d", "e"])
      end
    end

    describe ":first strategy" do
      it "takes the first value" do
        collapse = described_class.new(options: { merge: { name: :first } })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(name: "first"),
          Brainpipe::Namespace.new(name: "second"),
          Brainpipe::Namespace.new(name: "third")
        ]

        result = callable.call(namespaces)

        expect(result[0][:name]).to eq("first")
      end
    end

    describe ":last strategy" do
      it "takes the last value" do
        collapse = described_class.new(options: { merge: { name: :last } })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(name: "first"),
          Brainpipe::Namespace.new(name: "second"),
          Brainpipe::Namespace.new(name: "third")
        ]

        result = callable.call(namespaces)

        expect(result[0][:name]).to eq("third")
      end
    end

    describe ":equal strategy (default)" do
      it "passes when all values are equal" do
        collapse = described_class.new(options: { merge: { type: :equal } })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(type: "same"),
          Brainpipe::Namespace.new(type: "same"),
          Brainpipe::Namespace.new(type: "same")
        ]

        result = callable.call(namespaces)

        expect(result[0][:type]).to eq("same")
      end

      it "raises error when values differ" do
        collapse = described_class.new(options: { merge: { type: :equal } })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(type: "a"),
          Brainpipe::Namespace.new(type: "b")
        ]

        expect { callable.call(namespaces) }
          .to raise_error(Brainpipe::ExecutionError, /conflicting values/i)
      end

      it "is the default strategy for fields not in merge:" do
        collapse = described_class.new(options: {})
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(field: "different"),
          Brainpipe::Namespace.new(field: "values")
        ]

        expect { callable.call(namespaces) }
          .to raise_error(Brainpipe::ExecutionError, /conflicting values/i)
      end

      it "passes for default strategy when values are equal" do
        collapse = described_class.new(options: {})
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(field: "same"),
          Brainpipe::Namespace.new(field: "same")
        ]

        result = callable.call(namespaces)

        expect(result[0][:field]).to eq("same")
      end
    end

    describe ":distinct strategy" do
      it "passes when all values are unique" do
        collapse = described_class.new(options: { merge: { ids: :distinct } })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(ids: 1),
          Brainpipe::Namespace.new(ids: 2),
          Brainpipe::Namespace.new(ids: 3)
        ]

        result = callable.call(namespaces)

        expect(result[0][:ids]).to eq([1, 2, 3])
      end

      it "raises error when values have duplicates" do
        collapse = described_class.new(options: { merge: { ids: :distinct } })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(ids: 1),
          Brainpipe::Namespace.new(ids: 2),
          Brainpipe::Namespace.new(ids: 1)
        ]

        expect { callable.call(namespaces) }
          .to raise_error(Brainpipe::ExecutionError, /duplicate values/i)
      end
    end

    describe "multiple merge strategies" do
      it "applies different strategies to different fields" do
        collapse = described_class.new(options: {
          merge: {
            items: :collect,
            total: :sum,
            name: :first
          }
        })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(items: "a", total: 10, name: "first"),
          Brainpipe::Namespace.new(items: "b", total: 20, name: "second")
        ]

        result = callable.call(namespaces)

        expect(result[0][:items]).to eq(["a", "b"])
        expect(result[0][:total]).to eq(30)
        expect(result[0][:name]).to eq("first")
      end
    end

    describe "Link operations after merge" do
      it "applies copy after merging" do
        collapse = described_class.new(options: {
          merge: { items: :collect },
          copy: { items: :all_items }
        })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(items: "a"),
          Brainpipe::Namespace.new(items: "b")
        ]

        result = callable.call(namespaces)

        expect(result[0][:items]).to eq(["a", "b"])
        expect(result[0][:all_items]).to eq(["a", "b"])
      end

      it "applies move after merging" do
        collapse = described_class.new(options: {
          merge: { items: :collect },
          move: { items: :all_items }
        })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(items: "a"),
          Brainpipe::Namespace.new(items: "b")
        ]

        result = callable.call(namespaces)

        expect(result[0].key?(:items)).to be false
        expect(result[0][:all_items]).to eq(["a", "b"])
      end

      it "applies set after merging" do
        collapse = described_class.new(options: {
          merge: { items: :collect },
          set: { collapsed: true }
        })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(items: "a"),
          Brainpipe::Namespace.new(items: "b")
        ]

        result = callable.call(namespaces)

        expect(result[0][:collapsed]).to be true
      end

      it "applies delete after merging" do
        collapse = described_class.new(options: {
          merge: { items: :collect },
          delete: [:temp]
        })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(items: "a", temp: 1),
          Brainpipe::Namespace.new(items: "b", temp: 2)
        ]

        result = callable.call(namespaces)

        expect(result[0].key?(:temp)).to be false
      end
    end

    describe "empty input" do
      it "returns single empty namespace for empty input" do
        collapse = described_class.new(options: {})
        callable = collapse.create

        result = callable.call([])

        expect(result.length).to eq(1)
        expect(result[0].keys).to be_empty
      end
    end

    describe "single namespace input" do
      it "passes through single namespace unchanged (except Link operations)" do
        collapse = described_class.new(options: { merge: { items: :collect } })
        callable = collapse.create
        namespaces = [Brainpipe::Namespace.new(items: "only", other: "preserved")]

        result = callable.call(namespaces)

        expect(result.length).to eq(1)
        expect(result[0][:items]).to eq(["only"])
        expect(result[0][:other]).to eq("preserved")
      end
    end

    describe "handling nil values" do
      it "skips nil values in merge" do
        collapse = described_class.new(options: { merge: { items: :collect } })
        callable = collapse.create
        namespaces = [
          Brainpipe::Namespace.new(items: "a"),
          Brainpipe::Namespace.new(other: "no items field"),
          Brainpipe::Namespace.new(items: "b")
        ]

        result = callable.call(namespaces)

        expect(result[0][:items]).to eq(["a", "b"])
      end
    end
  end
end
