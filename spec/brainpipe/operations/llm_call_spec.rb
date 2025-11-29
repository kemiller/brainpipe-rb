require "tempfile"

RSpec.describe Brainpipe::Operations::LlmCall do
  let(:model_config) do
    Brainpipe::ModelConfig.new(
      name: :test_model,
      provider: :openai,
      model: "gpt-4",
      capabilities: [:text_to_text]
    )
  end

  let(:image_model_config) do
    Brainpipe::ModelConfig.new(
      name: :image_model,
      provider: :google_ai,
      model: "gemini-2.0-flash",
      capabilities: [:text_to_text, :text_image_to_text]
    )
  end

  describe "#initialize" do
    it "raises ConfigurationError without prompt or prompt_file" do
      expect {
        described_class.new(
          model: model_config,
          options: { inputs: { text: :string }, outputs: { result: :string } }
        )
      }.to raise_error(Brainpipe::ConfigurationError, /requires 'prompt' or 'prompt_file'/)
    end

    it "raises ConfigurationError without inputs" do
      expect {
        described_class.new(
          model: model_config,
          options: { prompt: "test", outputs: { result: :string } }
        )
      }.to raise_error(Brainpipe::ConfigurationError, /requires at least one input/)
    end

    it "raises ConfigurationError without outputs" do
      expect {
        described_class.new(
          model: model_config,
          options: { prompt: "test", inputs: { text: :string } }
        )
      }.to raise_error(Brainpipe::ConfigurationError, /requires at least one output/)
    end

    it "raises ConfigurationError for invalid capability" do
      expect {
        described_class.new(
          model: model_config,
          options: { prompt: "test", capability: :invalid, inputs: { text: :string }, outputs: { result: :string } }
        )
      }.to raise_error(Brainpipe::ConfigurationError, /Invalid capability/)
    end

    it "raises CapabilityMismatchError when model lacks capability" do
      expect {
        described_class.new(
          model: model_config,
          options: { prompt: "test", capability: :text_to_image, inputs: { text: :string }, outputs: { result: :image } }
        )
      }.to raise_error(Brainpipe::CapabilityMismatchError, /requires 'text_to_image' capability/)
    end

    it "accepts valid configuration" do
      op = described_class.new(
        model: model_config,
        options: { prompt: "Hello {{{ name }}}", inputs: { name: :string }, outputs: { greeting: :string } }
      )
      expect(op).to be_a(described_class)
    end
  end

  describe "#required_model_capability" do
    it "returns configured capability" do
      op = described_class.new(
        model: model_config,
        options: { prompt: "test", inputs: { text: :string }, outputs: { result: :string } }
      )
      expect(op.required_model_capability).to eq(:text_to_text)
    end

    it "returns custom capability when specified" do
      op = described_class.new(
        model: image_model_config,
        options: { prompt: "test", capability: :text_image_to_text, inputs: { text: :string }, outputs: { result: :string } }
      )
      expect(op.required_model_capability).to eq(:text_image_to_text)
    end
  end

  describe "#declared_reads" do
    it "returns input types" do
      op = described_class.new(
        model: model_config,
        options: { prompt: "test", inputs: { text: :string, count: :integer }, outputs: { result: :string } }
      )
      reads = op.declared_reads

      expect(reads[:text]).to eq({ type: String, optional: false })
      expect(reads[:count]).to eq({ type: Integer, optional: false })
    end

    it "handles optional inputs" do
      op = described_class.new(
        model: model_config,
        options: {
          prompt: "test",
          inputs: { text: { type: :string, optional: true } },
          outputs: { result: :string }
        }
      )
      reads = op.declared_reads

      expect(reads[:text]).to eq({ type: String, optional: true })
    end
  end

  describe "#declared_sets" do
    it "returns output types" do
      op = described_class.new(
        model: model_config,
        options: { prompt: "test", inputs: { text: :string }, outputs: { result: :string, count: :integer } }
      )
      sets = op.declared_sets

      expect(sets[:result]).to eq({ type: String, optional: false })
      expect(sets[:count]).to eq({ type: Integer, optional: false })
    end

    it "handles optional outputs" do
      op = described_class.new(
        model: model_config,
        options: {
          prompt: "test",
          inputs: { text: :string },
          outputs: { result: { type: :string, optional: true } }
        }
      )
      sets = op.declared_sets

      expect(sets[:result]).to eq({ type: String, optional: true })
    end
  end

  describe "#declared_deletes" do
    it "returns empty array" do
      op = described_class.new(
        model: model_config,
        options: { prompt: "test", inputs: { text: :string }, outputs: { result: :string } }
      )
      expect(op.declared_deletes).to eq([])
    end
  end

  describe "template loading" do
    context "with inline prompt" do
      it "uses prompt directly" do
        op = described_class.new(
          model: model_config,
          options: { prompt: "Hello {{{ name }}}", inputs: { name: :string }, outputs: { result: :string } }
        )
        expect(op).to be_a(described_class)
      end
    end

    context "with prompt_file" do
      let(:temp_file) do
        file = Tempfile.new(["prompt", ".mustache"])
        file.write("Template: {{{ content }}}")
        file.close
        file
      end

      after { temp_file.unlink }

      it "loads template from file" do
        op = described_class.new(
          model: model_config,
          options: { prompt_file: temp_file.path, inputs: { content: :string }, outputs: { result: :string } }
        )
        expect(op).to be_a(described_class)
      end

      it "raises ConfigurationError for missing file" do
        expect {
          described_class.new(
            model: model_config,
            options: { prompt_file: "/nonexistent/file.mustache", inputs: { text: :string }, outputs: { result: :string } }
          )
        }.to raise_error(Brainpipe::ConfigurationError, /Prompt file not found/)
      end
    end
  end

  describe "#create" do
    let(:mock_adapter) { instance_double(Brainpipe::ProviderAdapters::OpenAI) }

    before do
      allow(Brainpipe::ProviderAdapters).to receive(:for).with(:openai).and_return(mock_adapter)
    end

    context "text output" do
      it "renders template and parses JSON response" do
        allow(mock_adapter).to receive(:call).and_return({ "choices" => [{ "message" => { "content" => '{"greeting": "Hello World"}' } }] })
        allow(mock_adapter).to receive(:extract_text).and_return('{"greeting": "Hello World"}')

        op = described_class.new(
          model: model_config,
          options: { prompt: "Greet {{{ name }}}", inputs: { name: :string }, outputs: { greeting: :string } }
        )
        callable = op.create
        namespaces = [Brainpipe::Namespace.new(name: "World")]

        result = callable.call(namespaces)

        expect(result[0][:greeting]).to eq("Hello World")
      end

      it "interpolates variables using Mustache" do
        allow(mock_adapter).to receive(:call) do |prompt:, **_|
          expect(prompt).to eq("Hello Alice!")
          { "choices" => [{ "message" => { "content" => '{"result": "ok"}' } }] }
        end
        allow(mock_adapter).to receive(:extract_text).and_return('{"result": "ok"}')

        op = described_class.new(
          model: model_config,
          options: { prompt: "Hello {{{ name }}}!", inputs: { name: :string }, outputs: { result: :string } }
        )
        callable = op.create
        namespaces = [Brainpipe::Namespace.new(name: "Alice")]

        callable.call(namespaces)
      end

      it "handles Mustache sections for arrays" do
        allow(mock_adapter).to receive(:call) do |prompt:, **_|
          expect(prompt).to include("- apple")
          expect(prompt).to include("- banana")
          { "choices" => [{ "message" => { "content" => '{"result": "ok"}' } }] }
        end
        allow(mock_adapter).to receive(:extract_text).and_return('{"result": "ok"}')

        op = described_class.new(
          model: model_config,
          options: {
            prompt: "Items:{{# items }}\n- {{{ . }}}{{/ items }}",
            inputs: { items: :array },
            outputs: { result: :string }
          }
        )
        callable = op.create
        namespaces = [Brainpipe::Namespace.new(items: ["apple", "banana"])]

        callable.call(namespaces)
      end

      it "raises ExecutionError for missing required output field" do
        allow(mock_adapter).to receive(:call).and_return({})
        allow(mock_adapter).to receive(:extract_text).and_return('{"other": "value"}')

        op = described_class.new(
          model: model_config,
          options: { prompt: "test", inputs: { text: :string }, outputs: { missing: :string } }
        )
        callable = op.create
        namespaces = [Brainpipe::Namespace.new(text: "input")]

        expect { callable.call(namespaces) }.to raise_error(Brainpipe::ExecutionError, /Missing required output field 'missing'/)
      end

      it "allows missing optional output fields" do
        allow(mock_adapter).to receive(:call).and_return({})
        allow(mock_adapter).to receive(:extract_text).and_return('{"required": "value"}')

        op = described_class.new(
          model: model_config,
          options: {
            prompt: "test",
            inputs: { text: :string },
            outputs: { required: :string, optional_field: { type: :string, optional: true } }
          }
        )
        callable = op.create
        namespaces = [Brainpipe::Namespace.new(text: "input")]

        result = callable.call(namespaces)
        expect(result[0][:required]).to eq("value")
        expect(result[0].key?(:optional_field)).to be false
      end

      it "raises ExecutionError for invalid JSON response" do
        allow(mock_adapter).to receive(:call).and_return({})
        allow(mock_adapter).to receive(:extract_text).and_return("not valid json")

        op = described_class.new(
          model: model_config,
          options: { prompt: "test", inputs: { text: :string }, outputs: { result: :string } }
        )
        callable = op.create
        namespaces = [Brainpipe::Namespace.new(text: "input")]

        expect { callable.call(namespaces) }.to raise_error(Brainpipe::ExecutionError, /Failed to parse JSON/)
      end
    end

    context "image input handling" do
      let(:mock_image) { instance_double(Brainpipe::Image, mime_type: "image/png", base64: "abc123") }

      it "replaces images with placeholder in template context" do
        allow(mock_adapter).to receive(:call) do |prompt:, images:, **_|
          expect(prompt).to include("[IMAGE]")
          expect(images).to eq([mock_image])
          {}
        end
        allow(mock_adapter).to receive(:extract_text).and_return('{"description": "A cat"}')

        op = described_class.new(
          model: model_config,
          options: {
            prompt: "Describe this image: {{{ img }}}",
            inputs: { img: :image },
            outputs: { description: :string }
          }
        )
        callable = op.create
        namespaces = [Brainpipe::Namespace.new(img: mock_image)]

        callable.call(namespaces)
      end
    end

    context "image output" do
      let(:google_model_config) do
        Brainpipe::ModelConfig.new(
          name: :google_model,
          provider: :google_ai,
          model: "gemini-2.0-flash",
          capabilities: [:text_to_image]
        )
      end
      let(:mock_google_adapter) { instance_double(Brainpipe::ProviderAdapters::GoogleAI) }
      let(:output_image) { instance_double(Brainpipe::Image) }

      before do
        allow(Brainpipe::ProviderAdapters).to receive(:for).with(:google_ai).and_return(mock_google_adapter)
      end

      it "extracts image via adapter" do
        allow(mock_google_adapter).to receive(:call).and_return({})
        allow(mock_google_adapter).to receive(:extract_image).and_return(output_image)

        op = described_class.new(
          model: google_model_config,
          options: {
            prompt: "Generate image of {{{ subject }}}",
            capability: :text_to_image,
            inputs: { subject: :string },
            outputs: { generated: :image }
          }
        )
        callable = op.create
        namespaces = [Brainpipe::Namespace.new(subject: "a sunset")]

        result = callable.call(namespaces)

        expect(result[0][:generated]).to eq(output_image)
      end

      it "raises ExecutionError when no image found" do
        allow(mock_google_adapter).to receive(:call).and_return({})
        allow(mock_google_adapter).to receive(:extract_image).and_return(nil)

        op = described_class.new(
          model: google_model_config,
          options: {
            prompt: "Generate image",
            capability: :text_to_image,
            inputs: { text: :string },
            outputs: { img: :image }
          }
        )
        callable = op.create
        namespaces = [Brainpipe::Namespace.new(text: "input")]

        expect { callable.call(namespaces) }.to raise_error(Brainpipe::ExecutionError, /No image found/)
      end
    end

    context "json_mode" do
      it "defaults to true for text outputs" do
        allow(mock_adapter).to receive(:call) do |json_mode:, **_|
          expect(json_mode).to be true
          {}
        end
        allow(mock_adapter).to receive(:extract_text).and_return('{"result": "ok"}')

        op = described_class.new(
          model: model_config,
          options: { prompt: "test", inputs: { text: :string }, outputs: { result: :string } }
        )
        callable = op.create
        callable.call([Brainpipe::Namespace.new(text: "input")])
      end

      it "defaults to false for image outputs" do
        google_config = Brainpipe::ModelConfig.new(
          name: :google,
          provider: :google_ai,
          model: "gemini",
          capabilities: [:text_to_image]
        )
        mock_google = instance_double(Brainpipe::ProviderAdapters::GoogleAI)
        allow(Brainpipe::ProviderAdapters).to receive(:for).with(:google_ai).and_return(mock_google)
        allow(mock_google).to receive(:call) do |json_mode:, **_|
          expect(json_mode).to be false
          {}
        end
        allow(mock_google).to receive(:extract_image).and_return(instance_double(Brainpipe::Image))

        op = described_class.new(
          model: google_config,
          options: {
            prompt: "test",
            capability: :text_to_image,
            inputs: { text: :string },
            outputs: { img: :image }
          }
        )
        callable = op.create
        callable.call([Brainpipe::Namespace.new(text: "input")])
      end

      it "can be explicitly overridden" do
        allow(mock_adapter).to receive(:call) do |json_mode:, **_|
          expect(json_mode).to be false
          {}
        end
        allow(mock_adapter).to receive(:extract_text).and_return('{"result": "ok"}')

        op = described_class.new(
          model: model_config,
          options: { prompt: "test", inputs: { text: :string }, outputs: { result: :string }, json_mode: false }
        )
        callable = op.create
        callable.call([Brainpipe::Namespace.new(text: "input")])
      end
    end

    it "processes multiple namespaces" do
      call_count = 0
      allow(mock_adapter).to receive(:call) do |prompt:, **_|
        call_count += 1
        {}
      end
      allow(mock_adapter).to receive(:extract_text).and_return('{"result": "processed"}')

      op = described_class.new(
        model: model_config,
        options: { prompt: "{{{ text }}}", inputs: { text: :string }, outputs: { result: :string } }
      )
      callable = op.create
      namespaces = [
        Brainpipe::Namespace.new(text: "first"),
        Brainpipe::Namespace.new(text: "second")
      ]

      result = callable.call(namespaces)

      expect(call_count).to eq(2)
      expect(result.size).to eq(2)
    end

    it "preserves existing namespace fields" do
      allow(mock_adapter).to receive(:call).and_return({})
      allow(mock_adapter).to receive(:extract_text).and_return('{"result": "output"}')

      op = described_class.new(
        model: model_config,
        options: { prompt: "test", inputs: { text: :string }, outputs: { result: :string } }
      )
      callable = op.create
      namespaces = [Brainpipe::Namespace.new(text: "input", other: "preserved")]

      result = callable.call(namespaces)

      expect(result[0][:other]).to eq("preserved")
      expect(result[0][:text]).to eq("input")
    end
  end
end
