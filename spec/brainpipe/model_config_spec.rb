RSpec.describe Brainpipe::ModelConfig do
  describe "#initialize" do
    it "creates config with required attributes" do
      config = described_class.new(
        name: :default,
        provider: :openai,
        model: "gpt-4o",
        capabilities: [:text_to_text]
      )

      expect(config.name).to eq(:default)
      expect(config.provider).to eq(:openai)
      expect(config.model).to eq("gpt-4o")
      expect(config.capabilities).to eq([:text_to_text])
      expect(config.options).to eq({})
    end

    it "accepts options hash" do
      config = described_class.new(
        name: :default,
        provider: :openai,
        model: "gpt-4o",
        capabilities: [:text_to_text],
        options: { temperature: 0.7 }
      )

      expect(config.options).to eq({ temperature: 0.7 })
    end

    it "converts string name to symbol" do
      config = described_class.new(
        name: "default",
        provider: :openai,
        model: "gpt-4o",
        capabilities: [:text_to_text]
      )

      expect(config.name).to eq(:default)
    end

    it "converts string provider to symbol" do
      config = described_class.new(
        name: :default,
        provider: "openai",
        model: "gpt-4o",
        capabilities: [:text_to_text]
      )

      expect(config.provider).to eq(:openai)
    end

    it "converts string capabilities to symbols" do
      config = described_class.new(
        name: :default,
        provider: :openai,
        model: "gpt-4o",
        capabilities: ["text_to_text", "image_to_text"]
      )

      expect(config.capabilities).to eq([:text_to_text, :image_to_text])
    end

    it "accepts single capability without array" do
      config = described_class.new(
        name: :default,
        provider: :openai,
        model: "gpt-4o",
        capabilities: :text_to_text
      )

      expect(config.capabilities).to eq([:text_to_text])
    end

    it "raises ConfigurationError for invalid capability" do
      expect {
        described_class.new(
          name: :default,
          provider: :openai,
          model: "gpt-4o",
          capabilities: [:invalid_capability]
        )
      }.to raise_error(Brainpipe::ConfigurationError, /Invalid capabilities.*invalid_capability/)
    end

    it "raises ConfigurationError listing all invalid capabilities" do
      expect {
        described_class.new(
          name: :default,
          provider: :openai,
          model: "gpt-4o",
          capabilities: [:foo, :bar, :text_to_text]
        )
      }.to raise_error(Brainpipe::ConfigurationError, /foo.*bar/)
    end
  end

  describe "immutability" do
    let(:config) do
      described_class.new(
        name: :default,
        provider: :openai,
        model: "gpt-4o",
        capabilities: [:text_to_text],
        options: { temperature: 0.7 }
      )
    end

    it "freezes the config after creation" do
      expect(config).to be_frozen
    end

    it "freezes capabilities array" do
      expect(config.capabilities).to be_frozen
    end

    it "freezes options hash" do
      expect(config.options).to be_frozen
    end

    it "freezes model string" do
      expect(config.model).to be_frozen
    end
  end

  describe "#has_capability?" do
    let(:config) do
      described_class.new(
        name: :default,
        provider: :openai,
        model: "gpt-4o",
        capabilities: [:text_to_text, :image_to_text]
      )
    end

    it "returns true for capability the model has (symbol)" do
      expect(config.has_capability?(:text_to_text)).to be true
    end

    it "returns true for capability the model has (string)" do
      expect(config.has_capability?("text_to_text")).to be true
    end

    it "returns false for capability the model lacks" do
      expect(config.has_capability?(:text_to_image)).to be false
    end
  end

  describe "#to_baml_client_registry" do
    let(:config) do
      described_class.new(
        name: :default,
        provider: :openai,
        model: "gpt-4o",
        capabilities: [:text_to_text]
      )
    end

    it "raises NotImplementedError (placeholder for Phase 13)" do
      expect { config.to_baml_client_registry }.to raise_error(NotImplementedError)
    end
  end
end
