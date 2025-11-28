RSpec.describe Brainpipe::Stage do
  def create_operation(reads: {}, sets: {}, deletes: [], &block)
    op_class = Class.new(Brainpipe::Operation) do
      reads.each { |name, opts| reads(name, opts[:type], optional: opts[:optional] || false) }
      sets.each { |name, opts| sets(name, opts[:type], optional: opts[:optional] || false) }
      deletes.each { |name| deletes(name) }

      if block
        execute(&block)
      else
        execute { |ns| ns }
      end
    end
    op_class.new
  end

  describe "#initialize" do
    it "stores the name as a symbol" do
      stage = described_class.new(name: "test", mode: :merge, operations: [])
      expect(stage.name).to eq(:test)
    end

    it "stores the mode" do
      stage = described_class.new(name: "test", mode: :fan_out, operations: [])
      expect(stage.mode).to eq(:fan_out)
    end

    it "stores operations frozen" do
      ops = [create_operation]
      stage = described_class.new(name: "test", mode: :merge, operations: ops)
      expect(stage.operations).to be_frozen
    end

    it "defaults merge_strategy to :last_in" do
      stage = described_class.new(name: "test", mode: :merge, operations: [])
      expect(stage.merge_strategy).to eq(:last_in)
    end

    it "accepts custom merge_strategy" do
      stage = described_class.new(name: "test", mode: :merge, operations: [], merge_strategy: :first_in)
      expect(stage.merge_strategy).to eq(:first_in)
    end

    it "freezes after initialization" do
      stage = described_class.new(name: "test", mode: :merge, operations: [])
      expect(stage).to be_frozen
    end

    context "mode validation" do
      it "accepts :merge mode" do
        expect { described_class.new(name: "test", mode: :merge, operations: []) }.not_to raise_error
      end

      it "accepts :fan_out mode" do
        expect { described_class.new(name: "test", mode: :fan_out, operations: []) }.not_to raise_error
      end

      it "accepts :batch mode" do
        expect { described_class.new(name: "test", mode: :batch, operations: []) }.not_to raise_error
      end

      it "raises for invalid mode" do
        expect { described_class.new(name: "test", mode: :invalid, operations: []) }
          .to raise_error(Brainpipe::ConfigurationError, /Invalid stage mode 'invalid'/)
      end

      it "accepts string modes and converts to symbols" do
        stage = described_class.new(name: "test", mode: "merge", operations: [])
        expect(stage.mode).to eq(:merge)
      end
    end

    context "merge_strategy validation" do
      it "accepts :last_in strategy" do
        expect { described_class.new(name: "test", mode: :merge, operations: [], merge_strategy: :last_in) }.not_to raise_error
      end

      it "accepts :first_in strategy" do
        expect { described_class.new(name: "test", mode: :merge, operations: [], merge_strategy: :first_in) }.not_to raise_error
      end

      it "accepts :collate strategy" do
        expect { described_class.new(name: "test", mode: :merge, operations: [], merge_strategy: :collate) }.not_to raise_error
      end

      it "accepts :disjoint strategy" do
        expect { described_class.new(name: "test", mode: :merge, operations: [], merge_strategy: :disjoint) }.not_to raise_error
      end

      it "raises for invalid merge_strategy" do
        expect { described_class.new(name: "test", mode: :merge, operations: [], merge_strategy: :invalid) }
          .to raise_error(Brainpipe::ConfigurationError, /Invalid merge strategy 'invalid'/)
      end
    end

    context "disjoint validation" do
      it "passes when operations have no overlapping sets" do
        op1 = create_operation(sets: { output_a: {} })
        op2 = create_operation(sets: { output_b: {} })

        expect { described_class.new(name: "test", mode: :merge, operations: [op1, op2], merge_strategy: :disjoint) }
          .not_to raise_error
      end

      it "raises when operations have overlapping sets" do
        op1 = create_operation(sets: { output: {} })
        op2 = create_operation(sets: { output: {} })

        expect { described_class.new(name: "test", mode: :merge, operations: [op1, op2], merge_strategy: :disjoint) }
          .to raise_error(Brainpipe::ConfigurationError, /Disjoint merge strategy requires non-overlapping sets/)
      end
    end
  end

  describe "#call" do
    context "empty input handling" do
      it "raises EmptyInputError for empty array" do
        stage = described_class.new(name: "test", mode: :merge, operations: [])
        expect { stage.call([]) }.to raise_error(Brainpipe::EmptyInputError, /Stage 'test' received empty input/)
      end
    end

    context "merge mode" do
      it "merges input namespaces before running operations" do
        received_ns = nil
        op = create_operation(reads: { a: {}, b: {} }) do |ns|
          received_ns = ns
          ns
        end

        stage = described_class.new(name: "test", mode: :merge, operations: [op])
        ns1 = Brainpipe::Namespace.new(a: 1)
        ns2 = Brainpipe::Namespace.new(b: 2)

        stage.call([ns1, ns2])

        expect(received_ns[:a]).to eq(1)
        expect(received_ns[:b]).to eq(2)
      end

      it "uses last-wins for conflicting properties during merge" do
        received_ns = nil
        op = create_operation(reads: { value: {} }) do |ns|
          received_ns = ns
          ns
        end

        stage = described_class.new(name: "test", mode: :merge, operations: [op])
        ns1 = Brainpipe::Namespace.new(value: "first")
        ns2 = Brainpipe::Namespace.new(value: "second")

        stage.call([ns1, ns2])

        expect(received_ns[:value]).to eq("second")
      end

      it "returns a single-element array" do
        op = create_operation { |ns| ns.merge(processed: true) }
        stage = described_class.new(name: "test", mode: :merge, operations: [op])

        result = stage.call([Brainpipe::Namespace.new(a: 1), Brainpipe::Namespace.new(b: 2)])

        expect(result.length).to eq(1)
      end
    end

    context "fan_out mode" do
      it "processes each namespace independently" do
        op = create_operation(reads: { input: {} }, sets: { output: {} }) do |ns|
          ns.merge(output: ns[:input].upcase)
        end

        stage = described_class.new(name: "test", mode: :fan_out, operations: [op])
        ns1 = Brainpipe::Namespace.new(input: "hello")
        ns2 = Brainpipe::Namespace.new(input: "world")

        result = stage.call([ns1, ns2])

        expect(result[0][:output]).to eq("HELLO")
        expect(result[1][:output]).to eq("WORLD")
      end

      it "preserves namespace count" do
        op = create_operation { |ns| ns }
        stage = described_class.new(name: "test", mode: :fan_out, operations: [op])

        result = stage.call([
          Brainpipe::Namespace.new(a: 1),
          Brainpipe::Namespace.new(a: 2),
          Brainpipe::Namespace.new(a: 3)
        ])

        expect(result.length).to eq(3)
      end

      it "runs operations concurrently" do
        thread_ids = Concurrent::Array.new

        op = create_operation(reads: { input: {} }, sets: { processed: {} }) do |ns|
          thread_ids << Thread.current.object_id
          sleep(0.05)
          ns.merge(processed: true)
        end

        stage = described_class.new(name: "test", mode: :fan_out, operations: [op])
        namespaces = 3.times.map { |i| Brainpipe::Namespace.new(input: i) }

        stage.call(namespaces)

        expect(thread_ids.length).to eq(3)
      end
    end

    context "batch mode" do
      it "passes entire array to operations" do
        received_count = Concurrent::AtomicFixnum.new(0)

        op_class = Class.new(Brainpipe::Operation) do
          define_method(:initialize) do |model: nil, options: {}|
            @model = model
            @options = options.freeze
            @received_count = received_count
          end

          define_method(:create) do
            counter = @received_count
            ->(namespaces) do
              counter.value = namespaces.length
              namespaces.map { |ns| ns.merge(batch_processed: true) }
            end
          end
        end

        op = op_class.new
        stage = described_class.new(name: "test", mode: :batch, operations: [op])
        namespaces = 3.times.map { |i| Brainpipe::Namespace.new(index: i) }

        result = stage.call(namespaces)

        expect(result.length).to eq(3)
        expect(result.all? { |ns| ns[:batch_processed] }).to be true
        expect(received_count.value).to eq(3)
      end
    end

    context "parallel operations" do
      it "runs multiple operations concurrently in merge mode" do
        execution_order = Concurrent::Array.new

        op1 = create_operation(sets: { a: {} }) do |ns|
          sleep(0.05)
          execution_order << :op1
          ns.merge(a: 1)
        end

        op2 = create_operation(sets: { b: {} }) do |ns|
          execution_order << :op2
          ns.merge(b: 2)
        end

        stage = described_class.new(name: "test", mode: :merge, operations: [op1, op2])
        stage.call([Brainpipe::Namespace.new])

        expect(execution_order).to include(:op1, :op2)
      end

      it "runs multiple operations concurrently in fan_out mode" do
        op1 = create_operation(sets: { a: {} }) { |ns| ns.merge(a: 1) }
        op2 = create_operation(sets: { b: {} }) { |ns| ns.merge(b: 2) }

        stage = described_class.new(name: "test", mode: :fan_out, operations: [op1, op2])
        result = stage.call([Brainpipe::Namespace.new(input: "test")])

        expect(result[0][:a]).to eq(1)
        expect(result[0][:b]).to eq(2)
      end
    end

    context "merge strategies" do
      let(:ns) { Brainpipe::Namespace.new(input: "test") }

      context ":last_in strategy" do
        it "uses last operation's result for conflicting properties" do
          op1 = create_operation(sets: { output: {} }) do |ns|
            sleep(0.01)
            ns.merge(output: "first", unique_a: "a")
          end

          op2 = create_operation(sets: { output: {} }) do |ns|
            ns.merge(output: "second", unique_b: "b")
          end

          stage = described_class.new(name: "test", mode: :merge, operations: [op1, op2], merge_strategy: :last_in)
          result = stage.call([ns])

          expect(result[0][:unique_a]).to eq("a")
          expect(result[0][:unique_b]).to eq("b")
        end
      end

      context ":first_in strategy" do
        it "uses first operation's result for conflicting properties" do
          op1 = create_operation(sets: { unique_a: {} }) do |ns|
            ns.merge(output: "first", unique_a: "a")
          end

          op2 = create_operation(sets: { unique_b: {} }) do |ns|
            sleep(0.01)
            ns.merge(output: "second", unique_b: "b")
          end

          stage = described_class.new(name: "test", mode: :merge, operations: [op1, op2], merge_strategy: :first_in)
          result = stage.call([ns])

          expect(result[0][:unique_a]).to eq("a")
          expect(result[0][:unique_b]).to eq("b")
        end
      end

      context ":collate strategy" do
        it "creates arrays for conflicting properties" do
          op1 = create_operation(sets: { output: {} }) { |ns| ns.merge(output: "first", unique_a: "a") }
          op2 = create_operation(sets: { output: {} }) { |ns| ns.merge(output: "second", unique_b: "b") }

          stage = described_class.new(name: "test", mode: :merge, operations: [op1, op2], merge_strategy: :collate)
          result = stage.call([ns])

          expect(result[0][:output]).to contain_exactly("first", "second")
          expect(result[0][:unique_a]).to eq("a")
          expect(result[0][:unique_b]).to eq("b")
        end

        it "keeps single values when not conflicting" do
          op1 = create_operation(sets: { a: {} }) { |ns| ns.merge(a: 1) }
          op2 = create_operation(sets: { b: {} }) { |ns| ns.merge(b: 2) }

          stage = described_class.new(name: "test", mode: :merge, operations: [op1, op2], merge_strategy: :collate)
          result = stage.call([ns])

          expect(result[0][:a]).to eq(1)
          expect(result[0][:b]).to eq(2)
        end
      end

      context ":disjoint strategy" do
        it "merges results directly when sets don't overlap" do
          op1 = create_operation(sets: { a: {} }) { |ns| ns.merge(a: 1) }
          op2 = create_operation(sets: { b: {} }) { |ns| ns.merge(b: 2) }

          stage = described_class.new(name: "test", mode: :merge, operations: [op1, op2], merge_strategy: :disjoint)
          result = stage.call([ns])

          expect(result[0][:a]).to eq(1)
          expect(result[0][:b]).to eq(2)
        end
      end
    end

    context "error handling" do
      it "allows all operations to complete before raising first error" do
        completed = Concurrent::Array.new

        op1 = create_operation do |ns|
          raise "boom"
        end

        op2 = create_operation(sets: { completed: {} }) do |ns|
          sleep(0.05)
          completed << true
          ns.merge(completed: true)
        end

        stage = described_class.new(name: "test", mode: :merge, operations: [op1, op2])

        expect { stage.call([Brainpipe::Namespace.new]) }.to raise_error(RuntimeError, "boom")
        sleep(0.1)
        expect(completed).to include(true)
      end

      it "raises the first error collected" do
        op1 = create_operation { raise "first error" }
        op2 = create_operation { raise "second error" }

        stage = described_class.new(name: "test", mode: :merge, operations: [op1, op2])

        expect { stage.call([Brainpipe::Namespace.new]) }.to raise_error(RuntimeError)
      end
    end
  end

  describe "#inputs" do
    it "aggregates reads from all operations" do
      op1 = create_operation(reads: { a: { type: String } })
      op2 = create_operation(reads: { b: { type: Integer } })

      stage = described_class.new(name: "test", mode: :merge, operations: [op1, op2])

      expect(stage.inputs.keys).to contain_exactly(:a, :b)
    end

    it "includes type information" do
      op = create_operation(reads: { input: { type: String } })
      stage = described_class.new(name: "test", mode: :merge, operations: [op])

      expect(stage.inputs[:input][:type]).to eq(String)
    end

    it "includes optional flag" do
      op = create_operation(reads: { input: { optional: true } })
      stage = described_class.new(name: "test", mode: :merge, operations: [op])

      expect(stage.inputs[:input][:optional]).to be true
    end
  end

  describe "#outputs" do
    it "aggregates sets from all operations" do
      op1 = create_operation(sets: { a: { type: String } })
      op2 = create_operation(sets: { b: { type: Integer } })

      stage = described_class.new(name: "test", mode: :merge, operations: [op1, op2])

      expect(stage.outputs.keys).to contain_exactly(:a, :b)
    end

    it "includes type information" do
      op = create_operation(sets: { output: { type: String } })
      stage = described_class.new(name: "test", mode: :merge, operations: [op])

      expect(stage.outputs[:output][:type]).to eq(String)
    end
  end

  describe "#validate!" do
    it "returns true when valid" do
      stage = described_class.new(name: "test", mode: :merge, operations: [])
      expect(stage.validate!).to be true
    end

    it "raises for disjoint strategy with overlapping sets" do
      op1 = create_operation(sets: { output: {} })
      op2 = create_operation(sets: { output: {} })

      expect {
        described_class.new(name: "test", mode: :merge, operations: [op1, op2], merge_strategy: :disjoint)
      }.to raise_error(Brainpipe::ConfigurationError, /overlapping sets/)
    end
  end

  describe "constants" do
    it "defines MODES" do
      expect(Brainpipe::Stage::MODES).to eq([:merge, :fan_out, :batch])
    end

    it "defines MERGE_STRATEGIES" do
      expect(Brainpipe::Stage::MERGE_STRATEGIES).to eq([:last_in, :first_in, :collate, :disjoint])
    end

    it "freezes MODES" do
      expect(Brainpipe::Stage::MODES).to be_frozen
    end

    it "freezes MERGE_STRATEGIES" do
      expect(Brainpipe::Stage::MERGE_STRATEGIES).to be_frozen
    end
  end

  describe "integration" do
    it "works end-to-end with independent parallel operations" do
      extract_op = create_operation(
        reads: { raw_text: { type: String } },
        sets: { words: {} }
      ) do |ns|
        ns.merge(words: ns[:raw_text].split)
      end

      length_op = create_operation(
        reads: { raw_text: { type: String } },
        sets: { char_count: { type: Integer } }
      ) do |ns|
        ns.merge(char_count: ns[:raw_text].length)
      end

      stage = described_class.new(
        name: "process",
        mode: :merge,
        operations: [extract_op, length_op]
      )

      result = stage.call([
        Brainpipe::Namespace.new(raw_text: "hello world foo bar")
      ])

      expect(result[0][:words]).to eq(["hello", "world", "foo", "bar"])
      expect(result[0][:char_count]).to eq(19)
      expect(result[0][:raw_text]).to eq("hello world foo bar")
    end

    it "works with fan_out mode for parallel namespace processing" do
      uppercase_op = create_operation(
        reads: { text: { type: String } },
        sets: { upper: { type: String } }
      ) do |ns|
        ns.merge(upper: ns[:text].upcase)
      end

      stage = described_class.new(
        name: "transform",
        mode: :fan_out,
        operations: [uppercase_op]
      )

      result = stage.call([
        Brainpipe::Namespace.new(text: "hello"),
        Brainpipe::Namespace.new(text: "world")
      ])

      expect(result[0][:upper]).to eq("HELLO")
      expect(result[1][:upper]).to eq("WORLD")
    end
  end
end
