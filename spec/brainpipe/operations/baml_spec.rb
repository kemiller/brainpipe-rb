RSpec.describe Brainpipe::Operations::Baml do
  before do
    Brainpipe::BamlAdapter.reset!
  end

  describe "#initialize" do
    it "raises ConfigurationError without function option" do
      allow(Brainpipe::BamlAdapter).to receive(:require_available!)

      expect { described_class.new(options: {}) }
        .to raise_error(Brainpipe::ConfigurationError, /requires 'function' option/)
    end

    it "raises ConfigurationError when BAML is not available" do
      expect { described_class.new(options: { function: :test }) }
        .to raise_error(Brainpipe::ConfigurationError, /BAML is not available/)
    end
  end

  context "with mocked BAML" do
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
        { summary: "Summary of: #{input[:text]}", word_count: input[:text].split.size }
      end
      mock
    end

    before do
      allow(Brainpipe::BamlAdapter).to receive(:require_available!)
      allow(Brainpipe::BamlAdapter).to receive(:function).with(:summarize).and_return(mock_baml_function)
    end

    describe "#initialize" do
      it "accepts function option" do
        op = described_class.new(options: { function: :summarize })
        expect(op).to be_a(described_class)
      end
    end

    describe "#declared_reads" do
      it "returns input schema from BAML function" do
        op = described_class.new(options: { function: :summarize })
        reads = op.declared_reads

        expect(reads).to eq({ text: { type: String, optional: false } })
      end

      context "with input mapping" do
        let(:translate_function) do
          mock = instance_double(Brainpipe::BamlFunction, name: :translate)
          allow(mock).to receive(:input_schema).and_return({
            text: { type: String, optional: false },
            target_language: { type: String, optional: false }
          })
          allow(mock).to receive(:output_schema).and_return({
            translated: { type: String, optional: false }
          })
          allow(mock).to receive(:call) { |input, **_| { translated: "[#{input[:target_language]}] #{input[:text]}" } }
          mock
        end

        before do
          allow(Brainpipe::BamlAdapter).to receive(:function).with(:translate).and_return(translate_function)
        end

        it "maps namespace fields to BAML fields" do
          op = described_class.new(options: {
            function: :translate,
            inputs: { text: :content, target_language: :lang }
          })
          reads = op.declared_reads

          expect(reads.keys).to contain_exactly(:content, :lang)
        end

        it "looks up types from prefix_schema" do
          op = described_class.new(options: {
            function: :translate,
            inputs: { text: :content, target_language: :lang }
          })
          prefix_schema = { content: { type: String, optional: false } }
          reads = op.declared_reads(prefix_schema)

          expect(reads[:content][:type]).to eq(String)
        end
      end
    end

    describe "#declared_sets" do
      it "returns output schema from BAML function" do
        op = described_class.new(options: { function: :summarize })
        sets = op.declared_sets

        expect(sets).to eq({
          summary: { type: String, optional: false },
          word_count: { type: Integer, optional: false }
        })
      end

      context "with output mapping" do
        it "maps BAML output fields to namespace fields" do
          op = described_class.new(options: {
            function: :summarize,
            outputs: { summary: :result_summary, word_count: :result_count }
          })
          sets = op.declared_sets

          expect(sets.keys).to contain_exactly(:result_summary, :result_count)
          expect(sets[:result_summary][:type]).to eq(String)
          expect(sets[:result_count][:type]).to eq(Integer)
        end
      end
    end

    describe "#declared_deletes" do
      it "returns empty array" do
        op = described_class.new(options: { function: :summarize })
        expect(op.declared_deletes).to eq([])
      end
    end

    describe "#required_model_capability" do
      it "requires text_to_text capability" do
        op = described_class.new(options: { function: :summarize })
        expect(op.required_model_capability).to eq(:text_to_text)
      end
    end

    describe "#create" do
      it "executes BAML function and merges output fields" do
        op = described_class.new(options: { function: :summarize })
        callable = op.create
        namespaces = [Brainpipe::Namespace.new(text: "hello world test")]

        result = callable.call(namespaces)

        expect(result[0][:summary]).to eq("Summary of: hello world test")
        expect(result[0][:word_count]).to eq(3)
      end

      it "preserves other namespace fields" do
        op = described_class.new(options: { function: :summarize })
        callable = op.create
        namespaces = [Brainpipe::Namespace.new(text: "test", other: "preserved")]

        result = callable.call(namespaces)

        expect(result[0][:other]).to eq("preserved")
        expect(result[0][:text]).to eq("test")
      end

      it "processes multiple namespaces" do
        op = described_class.new(options: { function: :summarize })
        callable = op.create
        namespaces = [
          Brainpipe::Namespace.new(text: "one"),
          Brainpipe::Namespace.new(text: "two words")
        ]

        result = callable.call(namespaces)

        expect(result[0][:word_count]).to eq(1)
        expect(result[1][:word_count]).to eq(2)
      end

      context "with input mapping" do
        let(:translate_function) do
          mock = instance_double(Brainpipe::BamlFunction, name: :translate)
          allow(mock).to receive(:input_schema).and_return({
            text: { type: String, optional: false },
            language: { type: String, optional: false }
          })
          allow(mock).to receive(:output_schema).and_return({
            translated: { type: String, optional: false }
          })
          allow(mock).to receive(:call) do |input, **_|
            { translated: "[#{input[:language]}] #{input[:text]}" }
          end
          mock
        end

        before do
          allow(Brainpipe::BamlAdapter).to receive(:function).with(:translate).and_return(translate_function)
        end

        it "maps namespace fields to BAML input" do
          op = described_class.new(options: {
            function: :translate,
            inputs: { text: :content, language: :target_lang }
          })
          callable = op.create
          namespaces = [Brainpipe::Namespace.new(content: "hello", target_lang: "es")]

          result = callable.call(namespaces)

          expect(result[0][:translated]).to eq("[es] hello")
        end
      end

      context "with output mapping" do
        it "maps BAML output to namespace fields" do
          op = described_class.new(options: {
            function: :summarize,
            outputs: { summary: :result, word_count: :count }
          })
          callable = op.create
          namespaces = [Brainpipe::Namespace.new(text: "hello world")]

          result = callable.call(namespaces)

          expect(result[0][:result]).to eq("Summary of: hello world")
          expect(result[0][:count]).to eq(2)
          expect(result[0].key?(:summary)).to be false
        end
      end
    end

    describe "with model" do
      let(:model_config) do
        Brainpipe::ModelConfig.new(
          name: :test_model,
          provider: :openai,
          model: "gpt-4o",
          capabilities: [:text_to_text]
        )
      end

      it "passes model to operation" do
        op = described_class.new(model: model_config, options: { function: :summarize })
        expect(op.model).to eq(model_config)
      end
    end
  end
end
