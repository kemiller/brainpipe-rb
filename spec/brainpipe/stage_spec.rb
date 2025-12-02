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
      stage = described_class.new(name: "test", operations: [])
      expect(stage.name).to eq(:test)
    end

    it "stores operations frozen" do
      ops = [create_operation]
      stage = described_class.new(name: "test", operations: ops)
      expect(stage.operations).to be_frozen
    end

    it "freezes after initialization" do
      stage = described_class.new(name: "test", operations: [])
      expect(stage).to be_frozen
    end

    it "stores optional timeout" do
      stage = described_class.new(name: "test", operations: [], timeout: 5)
      expect(stage.timeout).to eq(5)
    end

    it "defaults timeout to nil" do
      stage = described_class.new(name: "test", operations: [])
      expect(stage.timeout).to be_nil
    end
  end

  describe "#call" do
    context "empty input handling" do
      it "raises EmptyInputError for empty array" do
        stage = described_class.new(name: "test", operations: [])
        expect { stage.call([]) }.to raise_error(Brainpipe::EmptyInputError, /Stage 'test' received empty input/)
      end
    end

    context "basic execution" do
      it "passes namespaces to operations" do
        received_ns = nil
        op = create_operation(reads: { a: {}, b: {} }) do |ns|
          received_ns = ns
          ns
        end

        stage = described_class.new(name: "test", operations: [op])
        ns = Brainpipe::Namespace.new(a: 1, b: 2)

        stage.call([ns])

        expect(received_ns[:a]).to eq(1)
        expect(received_ns[:b]).to eq(2)
      end

      it "returns namespace array from operations" do
        op = create_operation { |ns| ns.merge(processed: true) }
        stage = described_class.new(name: "test", operations: [op])

        result = stage.call([Brainpipe::Namespace.new(a: 1)])

        expect(result.length).to eq(1)
        expect(result[0][:processed]).to be true
      end

      it "preserves namespace count" do
        op = create_operation { |ns| ns }
        stage = described_class.new(name: "test", operations: [op])

        result = stage.call([
          Brainpipe::Namespace.new(a: 1),
          Brainpipe::Namespace.new(a: 2),
          Brainpipe::Namespace.new(a: 3)
        ])

        expect(result.length).to eq(3)
      end
    end

    context "parallel operations" do
      it "runs multiple operations concurrently" do
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

        stage = described_class.new(name: "test", operations: [op1, op2])
        stage.call([Brainpipe::Namespace.new])

        expect(execution_order).to include(:op1, :op2)
      end

      it "merges results from parallel operations" do
        op1 = create_operation(sets: { a: {} }) { |ns| ns.merge(a: 1) }
        op2 = create_operation(sets: { b: {} }) { |ns| ns.merge(b: 2) }

        stage = described_class.new(name: "test", operations: [op1, op2])
        result = stage.call([Brainpipe::Namespace.new(input: "test")])

        expect(result[0][:a]).to eq(1)
        expect(result[0][:b]).to eq(2)
      end

      it "uses last-wins for conflicting properties" do
        op1 = create_operation(sets: { output: {} }) do |ns|
          ns.merge(output: "first", unique_a: "a")
        end

        op2 = create_operation(sets: { output: {} }) do |ns|
          ns.merge(output: "second", unique_b: "b")
        end

        stage = described_class.new(name: "test", operations: [op1, op2])
        result = stage.call([Brainpipe::Namespace.new])

        expect(result[0][:unique_a]).to eq("a")
        expect(result[0][:unique_b]).to eq("b")
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

        stage = described_class.new(name: "test", operations: [op1, op2])

        expect { stage.call([Brainpipe::Namespace.new]) }.to raise_error(RuntimeError, "boom")
        sleep(0.1)
        expect(completed).to include(true)
      end

      it "raises the first error collected" do
        op1 = create_operation { raise "first error" }
        op2 = create_operation { raise "second error" }

        stage = described_class.new(name: "test", operations: [op1, op2])

        expect { stage.call([Brainpipe::Namespace.new]) }.to raise_error(RuntimeError)
      end
    end
  end

  describe "#inputs" do
    it "aggregates reads from all operations" do
      op1 = create_operation(reads: { a: { type: String } })
      op2 = create_operation(reads: { b: { type: Integer } })

      stage = described_class.new(name: "test", operations: [op1, op2])

      expect(stage.inputs.keys).to contain_exactly(:a, :b)
    end

    it "includes type information" do
      op = create_operation(reads: { input: { type: String } })
      stage = described_class.new(name: "test", operations: [op])

      expect(stage.inputs[:input][:type]).to eq(String)
    end

    it "includes optional flag" do
      op = create_operation(reads: { input: { optional: true } })
      stage = described_class.new(name: "test", operations: [op])

      expect(stage.inputs[:input][:optional]).to be true
    end
  end

  describe "#outputs" do
    it "aggregates sets from all operations" do
      op1 = create_operation(sets: { a: { type: String } })
      op2 = create_operation(sets: { b: { type: Integer } })

      stage = described_class.new(name: "test", operations: [op1, op2])

      expect(stage.outputs.keys).to contain_exactly(:a, :b)
    end

    it "includes type information" do
      op = create_operation(sets: { output: { type: String } })
      stage = described_class.new(name: "test", operations: [op])

      expect(stage.outputs[:output][:type]).to eq(String)
    end
  end

  describe "#validate!" do
    it "returns true when valid" do
      stage = described_class.new(name: "test", operations: [])
      expect(stage.validate!).to be true
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
        operations: [extract_op, length_op]
      )

      result = stage.call([
        Brainpipe::Namespace.new(raw_text: "hello world foo bar")
      ])

      expect(result[0][:words]).to eq(["hello", "world", "foo", "bar"])
      expect(result[0][:char_count]).to eq(19)
      expect(result[0][:raw_text]).to eq("hello world foo bar")
    end

    it "works with multiple namespaces" do
      uppercase_op = create_operation(
        reads: { text: { type: String } },
        sets: { upper: { type: String } }
      ) do |ns|
        ns.merge(upper: ns[:text].upcase)
      end

      stage = described_class.new(
        name: "transform",
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

  describe "timeout behavior" do
    it "stores timeout from initialization" do
      stage = described_class.new(name: "test", operations: [], timeout: 5)
      expect(stage.timeout).to eq(5)
    end

    it "defaults timeout to nil" do
      stage = described_class.new(name: "test", operations: [])
      expect(stage.timeout).to be_nil
    end

    it "raises TimeoutError when stage times out" do
      slow_op = create_operation(sets: { result: {} }) do |ns|
        sleep(0.5)
        ns.merge(result: "done")
      end

      stage = described_class.new(name: "slow", operations: [slow_op], timeout: 0.1)

      expect { stage.call([Brainpipe::Namespace.new]) }
        .to raise_error(Brainpipe::TimeoutError, /Stage 'slow' timed out/)
    end

    it "completes when execution is within timeout" do
      fast_op = create_operation(sets: { result: {} }) { |ns| ns.merge(result: "done") }
      stage = described_class.new(name: "fast", operations: [fast_op], timeout: 5)

      result = stage.call([Brainpipe::Namespace.new])

      expect(result[0][:result]).to eq("done")
    end

    it "uses passed timeout when smaller than stage timeout" do
      slow_op = create_operation(sets: { result: {} }) do |ns|
        sleep(0.5)
        ns.merge(result: "done")
      end

      stage = described_class.new(name: "slow", operations: [slow_op], timeout: 10)

      expect { stage.call([Brainpipe::Namespace.new], timeout: 0.1) }
        .to raise_error(Brainpipe::TimeoutError)
    end

    it "uses stage timeout when smaller than passed timeout" do
      slow_op = create_operation(sets: { result: {} }) do |ns|
        sleep(0.5)
        ns.merge(result: "done")
      end

      stage = described_class.new(name: "slow", operations: [slow_op], timeout: 0.1)

      expect { stage.call([Brainpipe::Namespace.new], timeout: 10) }
        .to raise_error(Brainpipe::TimeoutError)
    end
  end
end
