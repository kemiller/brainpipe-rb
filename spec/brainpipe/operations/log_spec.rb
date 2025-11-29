RSpec.describe Brainpipe::Operations::Log do
  describe "#initialize" do
    it "accepts no options" do
      log = described_class.new
      expect(log).to be_a(described_class)
    end

    it "accepts fields option" do
      log = described_class.new(options: { fields: [:name, :value] })
      expect(log).to be_a(described_class)
    end

    it "accepts message option" do
      log = described_class.new(options: { message: "Processing item" })
      expect(log).to be_a(described_class)
    end

    it "accepts level option" do
      log = described_class.new(options: { level: :warn })
      expect(log).to be_a(described_class)
    end

    it "validates level option" do
      expect { described_class.new(options: { level: :invalid }) }
        .to raise_error(Brainpipe::ConfigurationError, /level/)
    end

    it "accepts logger option" do
      logger = double("logger")
      log = described_class.new(options: { logger: logger })
      expect(log).to be_a(described_class)
    end
  end

  describe "#declared_reads" do
    it "returns empty (pure passthrough)" do
      log = described_class.new(options: { fields: [:name] })
      expect(log.declared_reads).to eq({})
    end
  end

  describe "#declared_sets" do
    it "returns empty (pure passthrough)" do
      log = described_class.new(options: { fields: [:name] })
      expect(log.declared_sets).to eq({})
    end
  end

  describe "#declared_deletes" do
    it "returns empty (pure passthrough)" do
      log = described_class.new(options: { fields: [:name] })
      expect(log.declared_deletes).to eq([])
    end
  end

  describe "#create" do
    it "returns namespaces unchanged" do
      log = described_class.new
      callable = log.create
      namespaces = [
        Brainpipe::Namespace.new(a: 1, b: 2),
        Brainpipe::Namespace.new(c: 3)
      ]

      result = callable.call(namespaces)

      expect(result).to eq(namespaces)
    end

    it "logs to stderr by default" do
      log = described_class.new(options: { message: "Test" })
      callable = log.create
      namespaces = [Brainpipe::Namespace.new(value: 42)]

      expect { callable.call(namespaces) }.to output(/INFO.*Test/).to_stderr
    end

    it "logs specific fields when provided" do
      log = described_class.new(options: { fields: [:name, :count] })
      callable = log.create
      namespaces = [Brainpipe::Namespace.new(name: "test", count: 5, extra: "ignored")]

      expect { callable.call(namespaces) }.to output(/name="test".*count=5/).to_stderr
    end

    it "logs all fields when no fields specified" do
      log = described_class.new
      callable = log.create
      namespaces = [Brainpipe::Namespace.new(a: 1, b: 2)]

      expect { callable.call(namespaces) }.to output(/a.*1.*b.*2/).to_stderr
    end

    it "uses custom logger when provided" do
      logger = double("logger")
      expect(logger).to receive(:info).with(anything)

      log = described_class.new(options: { logger: logger })
      callable = log.create
      namespaces = [Brainpipe::Namespace.new(value: 1)]

      callable.call(namespaces)
    end

    it "uses specified log level" do
      logger = double("logger")
      expect(logger).to receive(:warn).with(anything)

      log = described_class.new(options: { logger: logger, level: :warn })
      callable = log.create
      namespaces = [Brainpipe::Namespace.new(value: 1)]

      callable.call(namespaces)
    end

    it "logs multiple namespaces" do
      log = described_class.new(options: { fields: [:id] })
      callable = log.create
      namespaces = [
        Brainpipe::Namespace.new(id: 1),
        Brainpipe::Namespace.new(id: 2),
        Brainpipe::Namespace.new(id: 3)
      ]

      expect { callable.call(namespaces) }.to output(/id=1.*id=2.*id=3/m).to_stderr
    end

    it "includes message prefix when provided" do
      log = described_class.new(options: { message: "Processing", fields: [:id] })
      callable = log.create
      namespaces = [Brainpipe::Namespace.new(id: 42)]

      expect { callable.call(namespaces) }.to output(/Processing:.*id=42/).to_stderr
    end
  end
end
