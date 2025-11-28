RSpec.describe Brainpipe::ModelRegistry do
  let(:registry) { described_class.new }

  let(:config) do
    Brainpipe::ModelConfig.new(
      name: :default,
      provider: :openai,
      model: "gpt-4o",
      capabilities: [:text_to_text]
    )
  end

  describe "#register" do
    it "stores model config by name" do
      registry.register(:default, config)
      expect(registry.get(:default)).to eq(config)
    end

    it "converts string name to symbol" do
      registry.register("default", config)
      expect(registry.get(:default)).to eq(config)
    end

    it "raises ArgumentError if config is not ModelConfig" do
      expect {
        registry.register(:default, { provider: :openai })
      }.to raise_error(ArgumentError, /Expected ModelConfig/)
    end

    it "overwrites existing registration" do
      other_config = Brainpipe::ModelConfig.new(
        name: :default,
        provider: :anthropic,
        model: "claude-3",
        capabilities: [:text_to_text]
      )

      registry.register(:default, config)
      registry.register(:default, other_config)

      expect(registry.get(:default).provider).to eq(:anthropic)
    end
  end

  describe "#get" do
    before { registry.register(:default, config) }

    it "returns registered model by symbol" do
      expect(registry.get(:default)).to eq(config)
    end

    it "returns registered model by string" do
      expect(registry.get("default")).to eq(config)
    end

    it "raises MissingModelError for unregistered model" do
      expect {
        registry.get(:unknown)
      }.to raise_error(Brainpipe::MissingModelError, /Model 'unknown' not found/)
    end
  end

  describe "#get?" do
    before { registry.register(:default, config) }

    it "returns registered model" do
      expect(registry.get?(:default)).to eq(config)
    end

    it "returns nil for unregistered model" do
      expect(registry.get?(:unknown)).to be_nil
    end

    it "accepts string keys" do
      expect(registry.get?("default")).to eq(config)
    end
  end

  describe "#clear!" do
    it "removes all registered models" do
      registry.register(:default, config)
      registry.clear!

      expect(registry.get?(:default)).to be_nil
    end
  end

  describe "#names" do
    it "returns empty array when no models registered" do
      expect(registry.names).to eq([])
    end

    it "returns names of registered models" do
      other_config = Brainpipe::ModelConfig.new(
        name: :fast,
        provider: :anthropic,
        model: "claude-3-haiku",
        capabilities: [:text_to_text]
      )

      registry.register(:default, config)
      registry.register(:fast, other_config)

      expect(registry.names).to contain_exactly(:default, :fast)
    end
  end

  describe "#size" do
    it "returns 0 for empty registry" do
      expect(registry.size).to eq(0)
    end

    it "returns count of registered models" do
      other_config = Brainpipe::ModelConfig.new(
        name: :fast,
        provider: :anthropic,
        model: "claude-3-haiku",
        capabilities: [:text_to_text]
      )

      registry.register(:default, config)
      registry.register(:fast, other_config)

      expect(registry.size).to eq(2)
    end
  end
end
