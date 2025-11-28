RSpec.describe Brainpipe::Pipe do
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

  def create_stage(name:, mode:, operations:, merge_strategy: :last_in)
    Brainpipe::Stage.new(
      name: name,
      mode: mode,
      operations: operations,
      merge_strategy: merge_strategy
    )
  end

  describe "#initialize" do
    it "stores the name as a symbol" do
      op = create_operation(reads: { input: {} }, sets: { output: {} }) { |ns| ns.merge(output: "done") }
      stage = create_stage(name: "final", mode: :merge, operations: [op])

      pipe = described_class.new(name: "test", stages: [stage])
      expect(pipe.name).to eq(:test)
    end

    it "stores stages frozen" do
      op = create_operation(reads: { input: {} }, sets: { output: {} }) { |ns| ns.merge(output: "done") }
      stage = create_stage(name: "final", mode: :merge, operations: [op])

      pipe = described_class.new(name: "test", stages: [stage])
      expect(pipe.stages).to be_frozen
    end

    it "stores optional timeout" do
      op = create_operation { |ns| ns }
      stage = create_stage(name: "final", mode: :merge, operations: [op])

      pipe = described_class.new(name: "test", stages: [stage], timeout: 30)
      expect(pipe.timeout).to eq(30)
    end

    it "defaults timeout to nil" do
      op = create_operation { |ns| ns }
      stage = create_stage(name: "final", mode: :merge, operations: [op])

      pipe = described_class.new(name: "test", stages: [stage])
      expect(pipe.timeout).to be_nil
    end

    it "freezes after initialization" do
      op = create_operation { |ns| ns }
      stage = create_stage(name: "final", mode: :merge, operations: [op])

      pipe = described_class.new(name: "test", stages: [stage])
      expect(pipe).to be_frozen
    end
  end

  describe "#inputs" do
    it "returns inputs from first stage" do
      op1 = create_operation(reads: { raw_input: { type: String } }, sets: { processed: {} }) { |ns| ns.merge(processed: true) }
      op2 = create_operation(reads: { processed: {} }, sets: { final: {} }) { |ns| ns.merge(final: true) }

      stage1 = create_stage(name: "process", mode: :merge, operations: [op1])
      stage2 = create_stage(name: "finalize", mode: :merge, operations: [op2])

      pipe = described_class.new(name: "test", stages: [stage1, stage2])

      expect(pipe.inputs.keys).to include(:raw_input)
      expect(pipe.inputs[:raw_input][:type]).to eq(String)
    end

    it "is frozen" do
      op = create_operation(reads: { input: {} }, sets: { output: {} }) { |ns| ns.merge(output: "done") }
      stage = create_stage(name: "final", mode: :merge, operations: [op])

      pipe = described_class.new(name: "test", stages: [stage])
      expect(pipe.inputs).to be_frozen
    end

    it "returns empty hash when no stages" do
      op = create_operation { |ns| ns }
      stage = create_stage(name: "final", mode: :merge, operations: [op])

      pipe = described_class.new(name: "test", stages: [stage])
      expect(pipe.inputs).to eq({})
    end
  end

  describe "#outputs" do
    it "returns outputs from last stage" do
      op1 = create_operation(sets: { intermediate: {} }) { |ns| ns.merge(intermediate: true) }
      op2 = create_operation(reads: { intermediate: {} }, sets: { final_output: { type: String } }) do |ns|
        ns.merge(final_output: "done")
      end

      stage1 = create_stage(name: "process", mode: :merge, operations: [op1])
      stage2 = create_stage(name: "finalize", mode: :merge, operations: [op2])

      pipe = described_class.new(name: "test", stages: [stage1, stage2])

      expect(pipe.outputs.keys).to include(:final_output)
      expect(pipe.outputs[:final_output][:type]).to eq(String)
    end

    it "is frozen" do
      op = create_operation(reads: { input: {} }, sets: { output: {} }) { |ns| ns.merge(output: "done") }
      stage = create_stage(name: "final", mode: :merge, operations: [op])

      pipe = described_class.new(name: "test", stages: [stage])
      expect(pipe.outputs).to be_frozen
    end
  end

  describe "#validate!" do
    context "empty stages" do
      it "raises ConfigurationError when no stages provided" do
        expect { described_class.new(name: "test", stages: []) }
          .to raise_error(Brainpipe::ConfigurationError, /must have at least one stage/)
      end
    end

    context "last stage mode" do
      it "raises ConfigurationError when last stage is not merge mode" do
        op = create_operation { |ns| ns }
        stage = create_stage(name: "fanout", mode: :fan_out, operations: [op])

        expect { described_class.new(name: "test", stages: [stage]) }
          .to raise_error(Brainpipe::ConfigurationError, /last stage must be merge mode/)
      end

      it "allows merge mode as last stage" do
        op = create_operation { |ns| ns }
        stage = create_stage(name: "final", mode: :merge, operations: [op])

        expect { described_class.new(name: "test", stages: [stage]) }.not_to raise_error
      end

      it "allows fan_out followed by merge" do
        op1 = create_operation(sets: { processed: {} }) { |ns| ns.merge(processed: true) }
        op2 = create_operation(reads: { processed: {} }) { |ns| ns }

        stage1 = create_stage(name: "fanout", mode: :fan_out, operations: [op1])
        stage2 = create_stage(name: "merge", mode: :merge, operations: [op2])

        expect { described_class.new(name: "test", stages: [stage1, stage2]) }.not_to raise_error
      end

      it "allows batch followed by merge" do
        op1 = create_operation(sets: { processed: {} }) { |ns| ns.merge(processed: true) }
        op2 = create_operation(reads: { processed: {} }) { |ns| ns }

        stage1 = create_stage(name: "batch", mode: :batch, operations: [op1])
        stage2 = create_stage(name: "merge", mode: :merge, operations: [op2])

        expect { described_class.new(name: "test", stages: [stage1, stage2]) }.not_to raise_error
      end
    end

    context "stage compatibility" do
      it "raises IncompatibleStagesError when required inputs are missing" do
        op1 = create_operation(sets: { output_a: {} }) { |ns| ns.merge(output_a: "a") }
        op2 = create_operation(reads: { output_b: { type: String } }) { |ns| ns }

        stage1 = create_stage(name: "first", mode: :merge, operations: [op1])
        stage2 = create_stage(name: "second", mode: :merge, operations: [op2])

        expect { described_class.new(name: "test", stages: [stage1, stage2]) }
          .to raise_error(Brainpipe::IncompatibleStagesError, /output_b/)
      end

      it "allows when all required inputs are satisfied by previous outputs" do
        op1 = create_operation(sets: { output_a: {} }) { |ns| ns.merge(output_a: "a") }
        op2 = create_operation(reads: { output_a: {} }) { |ns| ns }

        stage1 = create_stage(name: "first", mode: :merge, operations: [op1])
        stage2 = create_stage(name: "second", mode: :merge, operations: [op2])

        expect { described_class.new(name: "test", stages: [stage1, stage2]) }.not_to raise_error
      end

      it "allows optional inputs that are not provided" do
        op1 = create_operation(sets: { output_a: {} }) { |ns| ns.merge(output_a: "a") }
        op2 = create_operation(reads: { output_a: {}, missing: { optional: true } }) { |ns| ns }

        stage1 = create_stage(name: "first", mode: :merge, operations: [op1])
        stage2 = create_stage(name: "second", mode: :merge, operations: [op2])

        expect { described_class.new(name: "test", stages: [stage1, stage2]) }.not_to raise_error
      end

      it "considers properties from multiple prior stages" do
        op1 = create_operation(sets: { from_stage1: {} }) { |ns| ns.merge(from_stage1: 1) }
        op2 = create_operation(reads: { from_stage1: {} }, sets: { from_stage2: {} }) do |ns|
          ns.merge(from_stage2: 2)
        end
        op3 = create_operation(reads: { from_stage1: {}, from_stage2: {} }) { |ns| ns }

        stage1 = create_stage(name: "first", mode: :merge, operations: [op1])
        stage2 = create_stage(name: "second", mode: :merge, operations: [op2])
        stage3 = create_stage(name: "third", mode: :merge, operations: [op3])

        expect { described_class.new(name: "test", stages: [stage1, stage2, stage3]) }.not_to raise_error
      end

      it "validates all stage pairs not just adjacent ones" do
        op1 = create_operation(sets: { a: {} }) { |ns| ns.merge(a: 1) }
        op2 = create_operation(reads: { a: {} }, sets: { b: {} }) { |ns| ns.merge(b: 2) }
        op3 = create_operation(reads: { c: { type: String } }) { |ns| ns }

        stage1 = create_stage(name: "first", mode: :merge, operations: [op1])
        stage2 = create_stage(name: "second", mode: :merge, operations: [op2])
        stage3 = create_stage(name: "third", mode: :merge, operations: [op3])

        expect { described_class.new(name: "test", stages: [stage1, stage2, stage3]) }
          .to raise_error(Brainpipe::IncompatibleStagesError, /c/)
      end
    end

    it "returns true when valid" do
      op = create_operation { |ns| ns }
      stage = create_stage(name: "final", mode: :merge, operations: [op])

      pipe = described_class.new(name: "test", stages: [stage])
      expect(pipe.validate!).to be true
    end
  end

  describe "#call" do
    it "accepts a hash and creates initial namespace" do
      op = create_operation(reads: { input: {} }, sets: { output: {} }) do |ns|
        ns.merge(output: ns[:input].upcase)
      end
      stage = create_stage(name: "process", mode: :merge, operations: [op])
      pipe = described_class.new(name: "test", stages: [stage])

      result = pipe.call(input: "hello")

      expect(result[:output]).to eq("HELLO")
    end

    it "accepts a Namespace directly" do
      op = create_operation(reads: { input: {} }, sets: { output: {} }) do |ns|
        ns.merge(output: ns[:input].upcase)
      end
      stage = create_stage(name: "process", mode: :merge, operations: [op])
      pipe = described_class.new(name: "test", stages: [stage])

      result = pipe.call(Brainpipe::Namespace.new(input: "world"))

      expect(result[:output]).to eq("WORLD")
    end

    it "raises EmptyInputError for nil properties" do
      op = create_operation { |ns| ns }
      stage = create_stage(name: "process", mode: :merge, operations: [op])
      pipe = described_class.new(name: "test", stages: [stage])

      expect { pipe.call(nil) }
        .to raise_error(Brainpipe::EmptyInputError, /received empty properties/)
    end

    it "executes stages in sequence" do
      execution_order = []

      op1 = create_operation(sets: { step1: {} }) do |ns|
        execution_order << :stage1
        ns.merge(step1: true)
      end
      op2 = create_operation(reads: { step1: {} }, sets: { step2: {} }) do |ns|
        execution_order << :stage2
        ns.merge(step2: true)
      end
      op3 = create_operation(reads: { step2: {} }, sets: { step3: {} }) do |ns|
        execution_order << :stage3
        ns.merge(step3: true)
      end

      stage1 = create_stage(name: "first", mode: :merge, operations: [op1])
      stage2 = create_stage(name: "second", mode: :merge, operations: [op2])
      stage3 = create_stage(name: "third", mode: :merge, operations: [op3])

      pipe = described_class.new(name: "test", stages: [stage1, stage2, stage3])
      pipe.call({})

      expect(execution_order).to eq([:stage1, :stage2, :stage3])
    end

    it "returns a single Namespace from merged last stage" do
      op = create_operation(sets: { result: {} }) { |ns| ns.merge(result: "done") }
      stage = create_stage(name: "final", mode: :merge, operations: [op])
      pipe = described_class.new(name: "test", stages: [stage])

      result = pipe.call({})

      expect(result).to be_a(Brainpipe::Namespace)
      expect(result[:result]).to eq("done")
    end

    it "preserves properties through pipeline" do
      op1 = create_operation(reads: { input: {} }, sets: { processed: {} }) do |ns|
        ns.merge(processed: ns[:input] + "_processed")
      end
      op2 = create_operation(reads: { processed: {} }, sets: { final: {} }) do |ns|
        ns.merge(final: ns[:processed] + "_final")
      end

      stage1 = create_stage(name: "process", mode: :merge, operations: [op1])
      stage2 = create_stage(name: "finalize", mode: :merge, operations: [op2])
      pipe = described_class.new(name: "test", stages: [stage1, stage2])

      result = pipe.call(input: "start")

      expect(result[:input]).to eq("start")
      expect(result[:processed]).to eq("start_processed")
      expect(result[:final]).to eq("start_processed_final")
    end
  end

  describe "integration" do
    it "supports multi-stage pipeline with transformations" do
      transform_op = create_operation(reads: { text: {} }, sets: { words: {} }) do |ns|
        ns.merge(words: ns[:text].split)
      end

      process_op = create_operation(reads: { words: {} }, sets: { processed: {} }) do |ns|
        ns.merge(processed: ns[:words].map(&:upcase))
      end

      final_op = create_operation(reads: { processed: {} }, sets: { result: {} }) do |ns|
        ns.merge(result: ns[:processed].join(", "))
      end

      stage1 = create_stage(name: "transform", mode: :merge, operations: [transform_op])
      stage2 = create_stage(name: "process", mode: :merge, operations: [process_op])
      stage3 = create_stage(name: "finalize", mode: :merge, operations: [final_op])

      pipe = described_class.new(name: "pipeline", stages: [stage1, stage2, stage3])
      result = pipe.call(text: "hello world foo")

      expect(result[:result]).to eq("HELLO, WORLD, FOO")
    end

    it "supports parallel operations within stages" do
      enrich_a = create_operation(reads: { input: {} }, sets: { enriched_a: {} }) do |ns|
        ns.merge(enriched_a: "#{ns[:input]}_a")
      end
      enrich_b = create_operation(reads: { input: {} }, sets: { enriched_b: {} }) do |ns|
        ns.merge(enriched_b: "#{ns[:input]}_b")
      end

      stage = create_stage(
        name: "enrich",
        mode: :merge,
        operations: [enrich_a, enrich_b],
        merge_strategy: :disjoint
      )
      pipe = described_class.new(name: "test", stages: [stage])

      result = pipe.call(input: "test")

      expect(result[:enriched_a]).to eq("test_a")
      expect(result[:enriched_b]).to eq("test_b")
      expect(result[:input]).to eq("test")
    end

    it "handles errors from stages" do
      error_op = create_operation { |ns| raise "boom" }
      stage = create_stage(name: "error", mode: :merge, operations: [error_op])
      pipe = described_class.new(name: "test", stages: [stage])

      expect { pipe.call({}) }.to raise_error(RuntimeError, "boom")
    end
  end

  describe "timeout behavior" do
    it "stores pipe timeout" do
      op = create_operation { |ns| ns }
      stage = create_stage(name: "test", mode: :merge, operations: [op])
      pipe = described_class.new(name: "test", stages: [stage], timeout: 30)

      expect(pipe.timeout).to eq(30)
    end

    it "defaults timeout to nil" do
      op = create_operation { |ns| ns }
      stage = create_stage(name: "test", mode: :merge, operations: [op])
      pipe = described_class.new(name: "test", stages: [stage])

      expect(pipe.timeout).to be_nil
    end

    it "completes when execution is within timeout" do
      fast_op = create_operation(sets: { result: {} }) do |ns|
        ns.merge(result: "done")
      end
      stage = create_stage(name: "fast", mode: :merge, operations: [fast_op])
      pipe = described_class.new(name: "test", stages: [stage], timeout: 5)

      result = pipe.call({})

      expect(result[:result]).to eq("done")
    end

    it "passes timeout configuration to stages" do
      op = create_operation(sets: { result: {} }) { |ns| ns.merge(result: "done") }
      stage = Brainpipe::Stage.new(name: "test", mode: :merge, operations: [op], timeout: 10)
      pipe = described_class.new(name: "test", stages: [stage], timeout: 5)

      result = pipe.call({})

      expect(result[:result]).to eq("done")
    end
  end
end
