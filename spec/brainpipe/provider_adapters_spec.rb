RSpec.describe Brainpipe::ProviderAdapters do
  after do
    described_class.reset!
  end

  describe ".normalize_provider" do
    it "converts hyphenated string to underscored symbol" do
      expect(described_class.normalize_provider("google-ai")).to eq(:google_ai)
    end

    it "converts underscored string to symbol" do
      expect(described_class.normalize_provider("google_ai")).to eq(:google_ai)
    end

    it "passes through symbols unchanged" do
      expect(described_class.normalize_provider(:google_ai)).to eq(:google_ai)
    end

    it "handles simple names without transformation" do
      expect(described_class.normalize_provider("openai")).to eq(:openai)
      expect(described_class.normalize_provider(:openai)).to eq(:openai)
    end
  end

  describe ".to_baml_provider" do
    it "converts underscored symbol to hyphenated string" do
      expect(described_class.to_baml_provider(:google_ai)).to eq("google-ai")
    end

    it "converts hyphenated string to hyphenated string" do
      expect(described_class.to_baml_provider("google-ai")).to eq("google-ai")
    end

    it "handles simple names without transformation" do
      expect(described_class.to_baml_provider(:openai)).to eq("openai")
    end
  end

  describe ".for" do
    it "returns OpenAI adapter for :openai" do
      adapter = described_class.for(:openai)
      expect(adapter).to be_a(Brainpipe::ProviderAdapters::OpenAI)
    end

    it "returns Anthropic adapter for :anthropic" do
      adapter = described_class.for(:anthropic)
      expect(adapter).to be_a(Brainpipe::ProviderAdapters::Anthropic)
    end

    it "returns GoogleAI adapter for :google_ai" do
      adapter = described_class.for(:google_ai)
      expect(adapter).to be_a(Brainpipe::ProviderAdapters::GoogleAI)
    end

    it "returns GoogleAI adapter for 'google-ai' string" do
      adapter = described_class.for("google-ai")
      expect(adapter).to be_a(Brainpipe::ProviderAdapters::GoogleAI)
    end

    it "returns GoogleAI adapter for 'google_ai' string" do
      adapter = described_class.for("google_ai")
      expect(adapter).to be_a(Brainpipe::ProviderAdapters::GoogleAI)
    end

    it "raises ConfigurationError for unknown provider" do
      expect {
        described_class.for(:unknown)
      }.to raise_error(Brainpipe::ConfigurationError, /Unknown provider.*unknown/)
    end
  end

  describe ".register" do
    it "allows registering custom adapters" do
      custom_adapter = Class.new(Brainpipe::ProviderAdapters::Base)
      described_class.register(:custom, custom_adapter)

      adapter = described_class.for(:custom)
      expect(adapter).to be_a(custom_adapter)
    end

    it "normalizes provider name on registration" do
      custom_adapter = Class.new(Brainpipe::ProviderAdapters::Base)
      described_class.register("my-custom-provider", custom_adapter)

      adapter = described_class.for(:my_custom_provider)
      expect(adapter).to be_a(custom_adapter)
    end
  end

  describe ".clear!" do
    it "removes all registered adapters" do
      described_class.clear!
      expect {
        described_class.for(:openai)
      }.to raise_error(Brainpipe::ConfigurationError)
    end
  end

  describe ".reset!" do
    it "restores default adapters after clear" do
      described_class.clear!
      described_class.reset!

      expect(described_class.for(:openai)).to be_a(Brainpipe::ProviderAdapters::OpenAI)
      expect(described_class.for(:anthropic)).to be_a(Brainpipe::ProviderAdapters::Anthropic)
      expect(described_class.for(:google_ai)).to be_a(Brainpipe::ProviderAdapters::GoogleAI)
    end
  end
end
