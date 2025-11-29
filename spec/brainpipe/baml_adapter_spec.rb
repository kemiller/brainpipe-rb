RSpec.describe Brainpipe::BamlAdapter do
  before do
    described_class.reset!
  end

  describe ".available?" do
    it "returns false when baml gem is not installed" do
      expect(described_class.available?).to be false
    end

    it "caches the result" do
      described_class.available?
      expect { described_class.available? }.not_to raise_error
    end
  end

  describe ".require_available!" do
    it "raises ConfigurationError when BAML is not available" do
      expect { described_class.require_available! }
        .to raise_error(Brainpipe::ConfigurationError, /BAML is not available/)
    end
  end

  describe ".function" do
    it "raises ConfigurationError when BAML is not available" do
      expect { described_class.function(:test_function) }
        .to raise_error(Brainpipe::ConfigurationError, /BAML is not available/)
    end
  end

  describe ".reset!" do
    it "clears cached availability" do
      described_class.available?
      described_class.reset!
      expect(described_class.instance_variable_get(:@available)).to be_nil
    end
  end

  describe ".to_baml_image" do
    context "when BAML is available" do
      before do
        allow(described_class).to receive(:require_available!)
        stub_const("Baml::Image", Class.new do
          def self.from_url(url)
            { type: :url, url: url }
          end

          def self.from_base64(mime_type, data)
            { type: :base64, mime_type: mime_type, data: data }
          end
        end)
      end

      it "converts URL-based image to BAML Image" do
        image = Brainpipe::Image.from_url("https://example.com/image.png")
        result = described_class.to_baml_image(image)
        expect(result).to eq({ type: :url, url: "https://example.com/image.png" })
      end

      it "converts base64-based image to BAML Image" do
        image = Brainpipe::Image.from_base64("aGVsbG8=", mime_type: "image/png")
        result = described_class.to_baml_image(image)
        expect(result).to eq({ type: :base64, mime_type: "image/png", data: "aGVsbG8=" })
      end
    end

    context "when BAML is not available" do
      it "raises ConfigurationError" do
        image = Brainpipe::Image.from_url("https://example.com/image.png")
        expect { described_class.to_baml_image(image) }
          .to raise_error(Brainpipe::ConfigurationError, /BAML is not available/)
      end
    end
  end

  describe ".build_client_registry" do
    it "returns nil when model_config is nil" do
      expect(described_class.build_client_registry(nil)).to be_nil
    end

    it "raises ConfigurationError when BAML is not available" do
      config = Brainpipe::ModelConfig.new(
        name: :default,
        provider: :openai,
        model: "gpt-4o",
        capabilities: [:text_to_text]
      )
      expect { described_class.build_client_registry(config) }
        .to raise_error(Brainpipe::ConfigurationError, /BAML is not available/)
    end
  end

  describe ".build_client_hash (via build_client_registry internals)" do
    let(:config) do
      Brainpipe::ModelConfig.new(
        name: :default,
        provider: :openai,
        model: "gpt-4o",
        capabilities: [:text_to_text],
        options: { api_key: "test-key" }
      )
    end

    let(:config_with_options) do
      Brainpipe::ModelConfig.new(
        name: :default,
        provider: :openai,
        model: "gpt-4o",
        capabilities: [:text_to_text],
        options: {
          api_key: "test-key",
          base_url: "https://api.example.com",
          temperature: 0.7,
          max_tokens: 1000
        }
      )
    end

    it "builds client hash with model and api_key" do
      client = described_class.send(:build_client_hash, config)
      expect(client["model"]).to eq("gpt-4o")
      expect(client["api_key"]).to eq("test-key")
    end

    it "includes optional settings when provided" do
      client = described_class.send(:build_client_hash, config_with_options)
      expect(client["base_url"]).to eq("https://api.example.com")
      expect(client["temperature"]).to eq(0.7)
      expect(client["max_tokens"]).to eq(1000)
    end
  end
end

RSpec.describe Brainpipe::BamlFunction do
  let(:mock_client) do
    client = Class.new do
      def summarize(text:, baml_options: nil)
        { summary: "Summary of: #{text}", word_count: text.split.size }
      end
    end.new
    client
  end

  let(:function) { described_class.new(name: :summarize, client: mock_client) }

  describe "#initialize" do
    it "stores name and client" do
      expect(function.name).to eq(:summarize)
      expect(function.client).to eq(mock_client)
    end

    it "is frozen" do
      expect(function).to be_frozen
    end

    it "raises MissingOperationError for unknown function" do
      expect { described_class.new(name: :unknown, client: mock_client) }
        .to raise_error(Brainpipe::MissingOperationError, /unknown/)
    end
  end

  describe "#input_schema" do
    it "extracts schema from method parameters" do
      schema = function.input_schema

      expect(schema[:text]).to eq({ type: Brainpipe::Any, optional: false })
    end

    it "excludes baml_options parameter" do
      expect(function.input_schema.keys).not_to include(:baml_options)
    end
  end

  describe "#output_schema" do
    it "returns empty hash when TypeBuilder not available" do
      expect(function.output_schema).to eq({})
    end
  end

  describe "#call" do
    it "calls the function with input" do
      result = function.call({ text: "hello world" })

      expect(result[:summary]).to eq("Summary of: hello world")
      expect(result[:word_count]).to eq(2)
    end

    it "passes client_registry when provided" do
      client_with_registry = Class.new do
        def test_func(input:, baml_options: nil)
          { result: input, registry: baml_options&.dig(:client_registry) }
        end
      end.new

      func = described_class.new(name: :test_func, client: client_with_registry)
      mock_registry = double("registry")

      result = func.call({ input: "test" }, client_registry: mock_registry)

      expect(result[:registry]).to eq(mock_registry)
    end
  end
end
