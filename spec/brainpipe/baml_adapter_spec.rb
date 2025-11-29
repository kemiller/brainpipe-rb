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
