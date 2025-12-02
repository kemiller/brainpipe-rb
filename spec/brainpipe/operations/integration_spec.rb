RSpec.describe "Built-in Operations Integration" do
  describe "Transform in a pipe" do
    it "renames field through the pipeline" do
      transform = Brainpipe::Operations::Transform.new(
        options: { from: :input, to: :output }
      )

      stage = Brainpipe::Stage.new(
        name: :transform,
        operations: [transform]
      )

      pipe = Brainpipe::Pipe.new(
        name: :transform_pipe,
        stages: [stage]
      )

      result = pipe.call(input: "hello")

      expect(result[:input]).to eq("hello")
      expect(result[:output]).to eq("hello")
    end

    it "chains multiple transforms" do
      transform1 = Brainpipe::Operations::Transform.new(
        options: { from: :a, to: :b, delete_source: true }
      )

      transform2 = Brainpipe::Operations::Transform.new(
        options: { from: :b, to: :c, delete_source: true }
      )

      stage1 = Brainpipe::Stage.new(
        name: :first,
        operations: [transform1]
      )

      stage2 = Brainpipe::Stage.new(
        name: :second,
        operations: [transform2]
      )

      pipe = Brainpipe::Pipe.new(
        name: :chained_transform,
        stages: [stage1, stage2]
      )

      result = pipe.call(a: "value")

      expect(result.key?(:a)).to be false
      expect(result.key?(:b)).to be false
      expect(result[:c]).to eq("value")
    end
  end

  describe "Filter in a pipe" do
    it "filters namespaces based on field value" do
      filter = Brainpipe::Operations::Filter.new(
        options: { field: :status, value: "active" }
      )

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
  end

  describe "Merge in a pipe" do
    it "combines multiple fields into one" do
      merge = Brainpipe::Operations::Merge.new(
        options: {
          sources: [:first_name, :last_name],
          target: :full_name,
          target_type: String
        }
      )

      stage = Brainpipe::Stage.new(
        name: :merge,
        operations: [merge]
      )

      pipe = Brainpipe::Pipe.new(
        name: :merge_pipe,
        stages: [stage]
      )

      result = pipe.call(first_name: "John", last_name: "Doe")

      expect(result[:full_name]).to eq("John Doe")
      expect(result[:first_name]).to eq("John")
      expect(result[:last_name]).to eq("Doe")
    end

    it "uses custom combiner" do
      merge = Brainpipe::Operations::Merge.new(
        options: {
          sources: [:a, :b, :c],
          target: :sum,
          target_type: Integer,
          combiner: ->(values) { values.sum }
        }
      )

      stage = Brainpipe::Stage.new(
        name: :sum,
        operations: [merge]
      )

      pipe = Brainpipe::Pipe.new(
        name: :sum_pipe,
        stages: [stage]
      )

      result = pipe.call(a: 10, b: 20, c: 30)

      expect(result[:sum]).to eq(60)
    end
  end

  describe "Log in a pipe" do
    it "logs without modifying data" do
      logger = double("logger")
      expect(logger).to receive(:debug).at_least(:once)

      log = Brainpipe::Operations::Log.new(
        options: { logger: logger, level: :debug, message: "Processing" }
      )

      passthrough = Class.new(Brainpipe::Operation) do
        reads :input
        sets :output

        execute do |ns|
          { output: ns[:input].upcase }
        end
      end.new

      stage = Brainpipe::Stage.new(
        name: :process,
        operations: [log, passthrough]
      )

      pipe = Brainpipe::Pipe.new(
        name: :log_pipe,
        stages: [stage]
      )

      result = pipe.call(input: "hello")

      expect(result[:output]).to eq("HELLO")
    end
  end

  describe "combined operations" do
    it "transform + merge pipeline" do
      transform = Brainpipe::Operations::Transform.new(
        options: { from: :name, to: :original_name }
      )

      merge = Brainpipe::Operations::Merge.new(
        options: {
          sources: [:original_name, :name],
          target: :full_name,
          target_type: String,
          combiner: ->(values) { values.join("_") }
        }
      )

      stage1 = Brainpipe::Stage.new(
        name: :transform,
        operations: [transform]
      )

      stage2 = Brainpipe::Stage.new(
        name: :merge,
        operations: [merge]
      )

      pipe = Brainpipe::Pipe.new(
        name: :combined,
        stages: [stage1, stage2]
      )

      result = pipe.call(name: "test")

      expect(result[:full_name]).to eq("test_test")
    end

    it "parallel operations" do
      transform1 = Brainpipe::Operations::Transform.new(
        options: { from: :input, to: :output_a }
      )

      transform2 = Brainpipe::Operations::Transform.new(
        options: { from: :input, to: :output_b }
      )

      stage = Brainpipe::Stage.new(
        name: :parallel,
        operations: [transform1, transform2]
      )

      pipe = Brainpipe::Pipe.new(
        name: :parallel_pipe,
        stages: [stage]
      )

      result = pipe.call(input: "value")

      expect(result[:output_a]).to eq("value")
      expect(result[:output_b]).to eq("value")
      expect(result[:input]).to eq("value")
    end
  end

  describe "Baml in a pipe" do
    let(:mock_baml_function) do
      mock = instance_double(Brainpipe::BamlFunction, name: :summarize)
      allow(mock).to receive(:input_schema).and_return({
        text: { type: String, optional: false }
      })
      allow(mock).to receive(:output_schema).and_return({
        summary: { type: String, optional: false },
        word_count: { type: Integer, optional: false }
      })
      allow(mock).to receive(:call) do |input, **_|
        { summary: "Summary: #{input[:text]}", word_count: input[:text].split.size }
      end
      mock
    end

    before do
      allow(Brainpipe::BamlAdapter).to receive(:require_available!)
      allow(Brainpipe::BamlAdapter).to receive(:function).with(:summarize).and_return(mock_baml_function)
    end

    it "executes BAML function in pipeline" do
      baml_op = Brainpipe::Operations::Baml.new(
        options: { function: :summarize }
      )

      stage = Brainpipe::Stage.new(
        name: :summarize,
        operations: [baml_op]
      )

      pipe = Brainpipe::Pipe.new(
        name: :baml_pipe,
        stages: [stage]
      )

      result = pipe.call(text: "Long document content")

      expect(result[:text]).to eq("Long document content")
      expect(result[:summary]).to eq("Summary: Long document content")
      expect(result[:word_count]).to eq(3)
    end

    it "chains BAML with transform" do
      transform = Brainpipe::Operations::Transform.new(
        options: { from: :input, to: :text }
      )

      baml_op = Brainpipe::Operations::Baml.new(
        options: { function: :summarize }
      )

      stage1 = Brainpipe::Stage.new(
        name: :transform,
        operations: [transform]
      )

      stage2 = Brainpipe::Stage.new(
        name: :summarize,
        operations: [baml_op]
      )

      pipe = Brainpipe::Pipe.new(
        name: :chained_baml,
        stages: [stage1, stage2]
      )

      result = pipe.call(input: "original content")

      expect(result[:summary]).to eq("Summary: original content")
    end

    it "uses input and output mapping for BAML fields" do
      translate_func = instance_double(Brainpipe::BamlFunction, name: :translate)
      allow(translate_func).to receive(:input_schema).and_return({
        text: { type: String, optional: false },
        language: { type: String, optional: false }
      })
      allow(translate_func).to receive(:output_schema).and_return({
        translated_text: { type: String, optional: false }
      })
      allow(translate_func).to receive(:call) do |input, **_|
        { translated_text: "[#{input[:language]}] #{input[:text]}" }
      end
      allow(Brainpipe::BamlAdapter).to receive(:function).with(:translate).and_return(translate_func)

      baml_op = Brainpipe::Operations::Baml.new(
        options: {
          function: :translate,
          inputs: { text: :content, language: :target_lang },
          outputs: { translated_text: :result }
        }
      )

      stage = Brainpipe::Stage.new(
        name: :translate,
        operations: [baml_op]
      )

      pipe = Brainpipe::Pipe.new(
        name: :translate_pipe,
        stages: [stage]
      )

      result = pipe.call(content: "hello world", target_lang: "es")

      expect(result[:result]).to eq("[es] hello world")
    end
  end

  describe "type safety validation" do
    it "validates type consistency in parallel operations" do
      op1_class = Class.new(Brainpipe::Operation) do
        sets :result, String
        execute { |ns| { result: "string" } }
      end
      stub_const("StringOp", op1_class)

      op2_class = Class.new(Brainpipe::Operation) do
        sets :result, Integer
        execute { |ns| { result: 42 } }
      end
      stub_const("IntegerOp", op2_class)

      stage = Brainpipe::Stage.new(
        name: :conflicting,
        operations: [StringOp.new, IntegerOp.new]
      )

      expect {
        Brainpipe::Pipe.new(
          name: :type_conflict_pipe,
          stages: [stage]
        )
      }.to raise_error(Brainpipe::TypeConflictError)
    end

    it "allows same type in parallel operations" do
      op1 = Class.new(Brainpipe::Operation) do
        sets :result, String
        execute { |ns| { result: "a" } }
      end.new

      op2 = Class.new(Brainpipe::Operation) do
        sets :result, String
        execute { |ns| { result: "b" } }
      end.new

      stage = Brainpipe::Stage.new(
        name: :compatible,
        operations: [op1, op2]
      )

      expect {
        Brainpipe::Pipe.new(
          name: :type_ok_pipe,
          stages: [stage]
        )
      }.not_to raise_error
    end
  end
end
