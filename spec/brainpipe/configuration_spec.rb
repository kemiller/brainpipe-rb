RSpec.describe Brainpipe::Configuration do
  let(:config) { described_class.new }

  after do
    Brainpipe.reset!
  end

  describe "#initialize" do
    it "sets config_path to nil" do
      expect(config.config_path).to be_nil
    end

    it "sets debug to false" do
      expect(config.debug).to be false
    end

    it "sets metrics_collector to nil" do
      expect(config.metrics_collector).to be_nil
    end

    it "sets max_threads to 10" do
      expect(config.max_threads).to eq(10)
    end

    it "sets thread_pool_timeout to 60" do
      expect(config.thread_pool_timeout).to eq(60)
    end

    it "creates an empty model registry" do
      expect(config.model_registry).to be_a(Brainpipe::ModelRegistry)
      expect(config.model_registry.size).to eq(0)
    end

    it "creates an empty operation registry" do
      expect(config.get_operation(:any)).to be_nil
    end

    it "creates empty autoload_paths" do
      expect(config.autoload_paths).to eq([])
    end
  end

  describe "basic attributes" do
    it "allows setting config_path" do
      config.config_path = "/path/to/config.yml"
      expect(config.config_path).to eq("/path/to/config.yml")
    end

    it "allows setting debug" do
      config.debug = true
      expect(config.debug).to be true
    end

    it "allows setting metrics_collector" do
      collector = double("collector")
      config.metrics_collector = collector
      expect(config.metrics_collector).to eq(collector)
    end

    it "allows setting max_threads" do
      config.max_threads = 20
      expect(config.max_threads).to eq(20)
    end

    it "allows setting thread_pool_timeout" do
      config.thread_pool_timeout = 120
      expect(config.thread_pool_timeout).to eq(120)
    end
  end

  describe "#secret_resolver=" do
    it "accepts a callable" do
      resolver = ->(ref) { "resolved:#{ref}" }
      config.secret_resolver = resolver
      expect(config.secret_resolver).to eq(resolver)
    end

    it "accepts nil" do
      config.secret_resolver = nil
      expect(config.secret_resolver).to be_nil
    end

    it "raises for non-callable" do
      expect {
        config.secret_resolver = "not a proc"
      }.to raise_error(Brainpipe::ConfigurationError, /must respond to #call/)
    end
  end

  describe "#model" do
    it "defines a model via block DSL" do
      config.model(:gpt4) do
        provider :openai
        model "gpt-4o"
        capabilities :text_to_text
      end

      model = config.model_registry.get(:gpt4)
      expect(model.name).to eq(:gpt4)
      expect(model.provider).to eq(:openai)
      expect(model.model).to eq("gpt-4o")
      expect(model.capabilities).to eq([:text_to_text])
    end

    it "allows multiple capabilities" do
      config.model(:multimodal) do
        provider :anthropic
        model "claude-3-opus"
        capabilities :text_to_text, :image_to_text
      end

      model = config.model_registry.get(:multimodal)
      expect(model.capabilities).to eq([:text_to_text, :image_to_text])
    end

    it "allows setting options" do
      config.model(:custom) do
        provider :openai
        model "gpt-4o"
        capabilities :text_to_text
        options temperature: 0.7, max_tokens: 1000
      end

      model = config.model_registry.get(:custom)
      expect(model.options[:temperature]).to eq(0.7)
      expect(model.options[:max_tokens]).to eq(1000)
    end

    it "allows setting api_key" do
      config.model(:with_key) do
        provider :openai
        model "gpt-4o"
        capabilities :text_to_text
        api_key "sk-test-key"
      end

      model = config.model_registry.get(:with_key)
      expect(model.options[:api_key]).to eq("sk-test-key")
    end

    it "raises without provider" do
      expect {
        config.model(:incomplete) do
          model "gpt-4o"
          capabilities :text_to_text
        end
      }.to raise_error(Brainpipe::ConfigurationError, /requires a provider/)
    end

    it "raises without model name" do
      expect {
        config.model(:incomplete) do
          provider :openai
          capabilities :text_to_text
        end
      }.to raise_error(Brainpipe::ConfigurationError, /requires a model name/)
    end

    it "raises without capabilities" do
      expect {
        config.model(:incomplete) do
          provider :openai
          model "gpt-4o"
        end
      }.to raise_error(Brainpipe::ConfigurationError, /requires at least one capability/)
    end
  end

  describe "#autoload_path" do
    it "adds a path to autoload_paths" do
      config.autoload_path("app/operations")
      expect(config.autoload_paths).to include(File.expand_path("app/operations"))
    end

    it "expands relative paths" do
      config.autoload_path("./lib")
      expect(config.autoload_paths.first).to match(%r{^/})
    end

    it "does not duplicate paths" do
      config.autoload_path("app/operations")
      config.autoload_path("app/operations")
      expect(config.autoload_paths.length).to eq(1)
    end

    it "allows multiple paths" do
      config.autoload_path("app/operations")
      config.autoload_path("lib/custom")
      expect(config.autoload_paths.length).to eq(2)
    end
  end

  describe "#register_operation" do
    let(:test_operation_class) do
      Class.new(Brainpipe::Operation)
    end

    it "registers an operation class by name" do
      config.register_operation(:custom_op, test_operation_class)
      expect(config.get_operation(:custom_op)).to eq(test_operation_class)
    end

    it "converts string names to symbols" do
      config.register_operation("custom_op", test_operation_class)
      expect(config.get_operation(:custom_op)).to eq(test_operation_class)
    end

    it "raises if class does not inherit from Operation" do
      expect {
        config.register_operation(:bad, String)
      }.to raise_error(Brainpipe::ConfigurationError, /must inherit from Brainpipe::Operation/)
    end
  end

  describe "#get_operation" do
    let(:test_operation_class) { Class.new(Brainpipe::Operation) }

    it "returns registered operation" do
      config.register_operation(:my_op, test_operation_class)
      expect(config.get_operation(:my_op)).to eq(test_operation_class)
    end

    it "returns nil for unregistered operation" do
      expect(config.get_operation(:unknown)).to be_nil
    end

    it "accepts string key" do
      config.register_operation(:my_op, test_operation_class)
      expect(config.get_operation("my_op")).to eq(test_operation_class)
    end
  end

  describe "#load_config!" do
    it "returns self for chaining" do
      expect(config.load_config!).to eq(config)
    end
  end

  describe "#reset!" do
    let(:test_operation_class) { Class.new(Brainpipe::Operation) }

    before do
      config.config_path = "/path/to/config.yml"
      config.debug = true
      config.max_threads = 20
      config.thread_pool_timeout = 120
      config.secret_resolver = ->(ref) { ref }
      config.autoload_path("app/operations")
      config.register_operation(:my_op, test_operation_class)
      config.model(:test_model) do
        provider :openai
        model "gpt-4o"
        capabilities :text_to_text
      end
    end

    it "resets config_path" do
      config.reset!
      expect(config.config_path).to be_nil
    end

    it "resets debug" do
      config.reset!
      expect(config.debug).to be false
    end

    it "resets max_threads" do
      config.reset!
      expect(config.max_threads).to eq(10)
    end

    it "resets thread_pool_timeout" do
      config.reset!
      expect(config.thread_pool_timeout).to eq(60)
    end

    it "resets secret_resolver" do
      config.reset!
      expect(config.secret_resolver).to be_nil
    end

    it "clears autoload_paths" do
      config.reset!
      expect(config.autoload_paths).to eq([])
    end

    it "clears operation registry" do
      config.reset!
      expect(config.get_operation(:my_op)).to be_nil
    end

    it "clears model registry" do
      config.reset!
      expect(config.model_registry.get?(:test_model)).to be_nil
    end

    it "returns self for chaining" do
      expect(config.reset!).to eq(config)
    end
  end

  describe "#build_secret_resolver" do
    it "returns a SecretResolver with configured resolver" do
      resolver_proc = ->(ref) { "secret:#{ref}" }
      config.secret_resolver = resolver_proc

      resolver = config.build_secret_resolver
      expect(resolver).to be_a(Brainpipe::SecretResolver)
    end

    it "returns a SecretResolver without resolver when none configured" do
      resolver = config.build_secret_resolver
      expect(resolver).to be_a(Brainpipe::SecretResolver)
    end
  end
end

RSpec.describe Brainpipe::ModelBuilder do
  describe "#build" do
    it "creates a ModelConfig with all attributes" do
      builder = described_class.new(:test)
      builder.provider(:openai)
      builder.model("gpt-4o")
      builder.capabilities(:text_to_text, :image_to_text)
      builder.options(temperature: 0.5)
      builder.api_key("test-key")

      config = builder.build

      expect(config).to be_a(Brainpipe::ModelConfig)
      expect(config.name).to eq(:test)
      expect(config.provider).to eq(:openai)
      expect(config.model).to eq("gpt-4o")
      expect(config.capabilities).to eq([:text_to_text, :image_to_text])
      expect(config.options[:temperature]).to eq(0.5)
      expect(config.options[:api_key]).to eq("test-key")
    end
  end
end

RSpec.describe "Brainpipe.configure integration" do
  after { Brainpipe.reset! }

  it "yields a Configuration instance" do
    Brainpipe.configure do |c|
      expect(c).to be_a(Brainpipe::Configuration)
    end
  end

  it "allows defining models" do
    Brainpipe.configure do |c|
      c.model(:default) do
        provider :openai
        model "gpt-4o"
        capabilities :text_to_text
      end
    end

    Brainpipe.load!
    model = Brainpipe.model(:default)
    expect(model.provider).to eq(:openai)
  end

  it "persists configuration across calls" do
    Brainpipe.configure do |c|
      c.debug = true
    end

    expect(Brainpipe.configuration.debug).to be true

    Brainpipe.configure do |c|
      c.max_threads = 5
    end

    expect(Brainpipe.configuration.debug).to be true
    expect(Brainpipe.configuration.max_threads).to eq(5)
  end

  it "resets configuration with Brainpipe.reset!" do
    Brainpipe.configure do |c|
      c.debug = true
    end

    Brainpipe.reset!

    expect(Brainpipe.configuration).to be_nil
  end
end
