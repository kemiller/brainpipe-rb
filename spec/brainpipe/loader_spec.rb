RSpec.describe Brainpipe::Loader do
  let(:config) { Brainpipe::Configuration.new }
  let(:loader) { described_class.new(config) }

  after do
    Brainpipe.reset!
  end

  describe "#initialize" do
    it "stores the configuration" do
      expect(loader.configuration).to eq(config)
    end
  end

  describe "#parse_yaml_file" do
    let(:valid_yaml) { "name: test\nvalue: 123" }
    let(:invalid_yaml) { "name: test\n  invalid:\nindentation" }

    around do |example|
      Dir.mktmpdir do |dir|
        @tmpdir = dir
        example.run
      end
    end

    it "parses valid YAML file" do
      path = File.join(@tmpdir, "test.yml")
      File.write(path, valid_yaml)

      result = loader.send(:parse_yaml_file, path)
      expect(result["name"]).to eq("test")
      expect(result["value"]).to eq(123)
    end

    it "raises InvalidYAMLError for invalid YAML" do
      path = File.join(@tmpdir, "invalid.yml")
      File.write(path, "foo: [bar")

      expect {
        loader.send(:parse_yaml_file, path)
      }.to raise_error(Brainpipe::InvalidYAMLError, /Invalid YAML/)
    end

    it "raises InvalidYAMLError for missing file" do
      expect {
        loader.send(:parse_yaml_file, "/nonexistent/file.yml")
      }.to raise_error(Brainpipe::InvalidYAMLError, /File not found/)
    end
  end

  describe "#load_config_file" do
    around do |example|
      Dir.mktmpdir do |dir|
        @tmpdir = dir
        example.run
      end
    end

    context "with valid config.yml" do
      before do
        FileUtils.mkdir_p(File.join(@tmpdir, "brainpipe"))
        config.config_path = File.join(@tmpdir, "brainpipe")
      end

      it "loads debug setting" do
        File.write(File.join(@tmpdir, "brainpipe", "config.yml"), "debug: true")

        loader.load_config_file
        expect(config.debug).to be true
      end

      it "loads model configurations" do
        yaml = <<~YAML
          models:
            default:
              provider: openai
              model: gpt-4o
              capabilities:
                - text_to_text
              options:
                temperature: 0.7
        YAML
        File.write(File.join(@tmpdir, "brainpipe", "config.yml"), yaml)

        loader.load_config_file

        model = config.model_registry.get(:default)
        expect(model.provider).to eq(:openai)
        expect(model.model).to eq("gpt-4o")
        expect(model.capabilities).to eq([:text_to_text])
        expect(model.options["temperature"]).to eq(0.7)
      end

      it "loads multiple models" do
        yaml = <<~YAML
          models:
            fast:
              provider: anthropic
              model: claude-3-haiku
              capabilities:
                - text_to_text
            vision:
              provider: openai
              model: gpt-4o
              capabilities:
                - text_to_text
                - image_to_text
        YAML
        File.write(File.join(@tmpdir, "brainpipe", "config.yml"), yaml)

        loader.load_config_file

        expect(config.model_registry.get(:fast).provider).to eq(:anthropic)
        expect(config.model_registry.get(:vision).capabilities).to include(:image_to_text)
      end

      it "resolves environment variables in options" do
        ENV["TEST_API_KEY"] = "secret-key-123"
        yaml = <<~YAML
          models:
            default:
              provider: openai
              model: gpt-4o
              capabilities:
                - text_to_text
              options:
                api_key: ${TEST_API_KEY}
        YAML
        File.write(File.join(@tmpdir, "brainpipe", "config.yml"), yaml)

        loader.load_config_file

        model = config.model_registry.get(:default)
        expect(model.options["api_key"]).to eq("secret-key-123")
      ensure
        ENV.delete("TEST_API_KEY")
      end
    end

    context "without config path" do
      it "returns nil without errors" do
        config.config_path = nil
        expect(loader.load_config_file).to be_nil
      end
    end

    context "with missing config.yml" do
      it "returns nil without errors" do
        config.config_path = @tmpdir
        expect(loader.load_config_file).to be_nil
      end
    end
  end

  describe "#load_pipe_file" do
    let(:test_operation) do
      Class.new(Brainpipe::Operation) do
        reads :input, String
        sets :output, String
        execute { |ns| ns.merge(output: ns[:input].upcase) }
      end
    end

    around do |example|
      Dir.mktmpdir do |dir|
        @tmpdir = dir
        example.run
      end
    end

    before do
      config.register_operation(:test_op, test_operation)
    end

    it "builds a pipe from YAML" do
      yaml = <<~YAML
        name: my_pipe
        stages:
          - name: stage1
            mode: merge
            operations:
              - type: test_op
      YAML
      path = File.join(@tmpdir, "my_pipe.yml")
      File.write(path, yaml)

      pipe = loader.load_pipe_file(path)
      expect(pipe.name).to eq(:my_pipe)
      expect(pipe.stages.length).to eq(1)
      expect(pipe.stages.first.name).to eq(:stage1)
    end

    it "raises InvalidYAMLError for missing name" do
      yaml = <<~YAML
        stages:
          - name: stage1
            mode: merge
            operations:
              - type: test_op
      YAML
      path = File.join(@tmpdir, "bad.yml")
      File.write(path, yaml)

      expect {
        loader.load_pipe_file(path)
      }.to raise_error(Brainpipe::InvalidYAMLError, /missing 'name'/)
    end

    it "raises InvalidYAMLError for missing stages" do
      yaml = "name: empty_pipe"
      path = File.join(@tmpdir, "bad.yml")
      File.write(path, yaml)

      expect {
        loader.load_pipe_file(path)
      }.to raise_error(Brainpipe::InvalidYAMLError, /missing 'stages'/)
    end
  end

  describe "#build_stage" do
    let(:test_operation) do
      Class.new(Brainpipe::Operation) do
        reads :input, String
        sets :output, String
      end
    end

    before do
      config.register_operation(:test_op, test_operation)
    end

    it "builds a stage with operations" do
      yaml_hash = {
        "name" => "my_stage",
        "mode" => "merge",
        "operations" => [
          { "type" => "test_op" }
        ]
      }

      stage = loader.build_stage(yaml_hash)
      expect(stage.name).to eq(:my_stage)
      expect(stage.mode).to eq(:merge)
      expect(stage.operations.length).to eq(1)
    end

    it "defaults mode to merge" do
      yaml_hash = {
        "name" => "my_stage",
        "operations" => [{ "type" => "test_op" }]
      }

      stage = loader.build_stage(yaml_hash)
      expect(stage.mode).to eq(:merge)
    end

    it "accepts merge_strategy" do
      yaml_hash = {
        "name" => "my_stage",
        "mode" => "merge",
        "merge_strategy" => "first_in",
        "operations" => [{ "type" => "test_op" }]
      }

      stage = loader.build_stage(yaml_hash)
      expect(stage.merge_strategy).to eq(:first_in)
    end

    it "raises InvalidYAMLError for missing stage name" do
      yaml_hash = {
        "mode" => "merge",
        "operations" => [{ "type" => "test_op" }]
      }

      expect {
        loader.build_stage(yaml_hash)
      }.to raise_error(Brainpipe::InvalidYAMLError, /missing 'name'/)
    end

    it "accepts timeout" do
      yaml_hash = {
        "name" => "my_stage",
        "mode" => "merge",
        "timeout" => 30,
        "operations" => [{ "type" => "test_op" }]
      }

      stage = loader.build_stage(yaml_hash)
      expect(stage.timeout).to eq(30)
    end

    it "defaults timeout to nil" do
      yaml_hash = {
        "name" => "my_stage",
        "mode" => "merge",
        "operations" => [{ "type" => "test_op" }]
      }

      stage = loader.build_stage(yaml_hash)
      expect(stage.timeout).to be_nil
    end
  end

  describe "#resolve_operation" do
    context "with registered operation" do
      let(:test_operation) { Class.new(Brainpipe::Operation) }

      it "returns registered operation class" do
        config.register_operation(:my_op, test_operation)
        expect(loader.resolve_operation("my_op")).to eq(test_operation)
      end

      it "accepts symbol lookup" do
        config.register_operation(:my_op, test_operation)
        expect(loader.resolve_operation(:my_op)).to eq(test_operation)
      end
    end

    context "with missing operation" do
      it "raises MissingOperationError" do
        expect {
          loader.resolve_operation("NonExistent")
        }.to raise_error(Brainpipe::MissingOperationError, /not found/)
      end
    end

    context "with class that doesn't inherit from Operation" do
      before do
        stub_const("NotAnOperation", Class.new)
      end

      it "raises ConfigurationError" do
        expect {
          loader.resolve_operation("NotAnOperation")
        }.to raise_error(Brainpipe::ConfigurationError, /must inherit from/)
      end
    end
  end

  describe "model resolution" do
    let(:model_config) do
      Brainpipe::ModelConfig.new(
        name: :default,
        provider: :openai,
        model: "gpt-4o",
        capabilities: [:text_to_text]
      )
    end

    let(:test_operation) do
      Class.new(Brainpipe::Operation) do
        reads :input, String
        sets :output, String
      end
    end

    let(:model_requiring_operation) do
      Class.new(Brainpipe::Operation) do
        reads :input, String
        sets :output, String
        requires_model :text_to_text
      end
    end

    before do
      config.model_registry.register(:default, model_config)
      config.register_operation(:test_op, test_operation)
      config.register_operation(:model_op, model_requiring_operation)
    end

    it "resolves model reference in operation" do
      yaml_hash = {
        "type" => "model_op",
        "model" => "default"
      }

      operation = loader.send(:build_operation, yaml_hash)
      expect(operation.model).to eq(model_config)
    end

    it "allows operation without model when not required" do
      yaml_hash = { "type" => "test_op" }

      operation = loader.send(:build_operation, yaml_hash)
      expect(operation.model).to be_nil
    end
  end

  describe "capability validation" do
    let(:text_model) do
      Brainpipe::ModelConfig.new(
        name: :text_only,
        provider: :openai,
        model: "gpt-4o",
        capabilities: [:text_to_text]
      )
    end

    let(:image_requiring_operation) do
      Class.new(Brainpipe::Operation) do
        reads :input, String
        sets :output, String
        requires_model :text_to_image
      end
    end

    let(:operation_requiring_model) do
      Class.new(Brainpipe::Operation) do
        reads :input, String
        sets :output, String
        requires_model :text_to_text
      end
    end

    before do
      config.model_registry.register(:text_only, text_model)
      config.register_operation(:image_op, image_requiring_operation)
      config.register_operation(:text_op, operation_requiring_model)
    end

    it "raises CapabilityMismatchError when model lacks required capability" do
      yaml_hash = {
        "type" => "image_op",
        "model" => "text_only"
      }

      expect {
        loader.send(:build_operation, yaml_hash)
      }.to raise_error(Brainpipe::CapabilityMismatchError, /text_to_image/)
    end

    it "raises CapabilityMismatchError when no model specified but required" do
      yaml_hash = { "type" => "text_op" }

      expect {
        loader.send(:build_operation, yaml_hash)
      }.to raise_error(Brainpipe::CapabilityMismatchError, /no model was specified/)
    end

    it "passes when model has required capability" do
      yaml_hash = {
        "type" => "text_op",
        "model" => "text_only"
      }

      operation = loader.send(:build_operation, yaml_hash)
      expect(operation.model).to eq(text_model)
    end
  end

  describe "#load_pipes" do
    let(:test_operation) do
      Class.new(Brainpipe::Operation) do
        reads :input, String
        sets :output, String
        execute { |ns| ns.merge(output: "processed") }
      end
    end

    around do |example|
      Dir.mktmpdir do |dir|
        @tmpdir = dir
        example.run
      end
    end

    before do
      config.register_operation(:test_op, test_operation)
    end

    it "loads all pipe files from pipes directory" do
      pipes_dir = File.join(@tmpdir, "brainpipe", "pipes")
      FileUtils.mkdir_p(pipes_dir)
      config.config_path = File.join(@tmpdir, "brainpipe")

      File.write(File.join(pipes_dir, "pipe1.yml"), <<~YAML)
        name: pipe1
        stages:
          - name: stage1
            mode: merge
            operations:
              - type: test_op
      YAML

      File.write(File.join(pipes_dir, "pipe2.yml"), <<~YAML)
        name: pipe2
        stages:
          - name: stage1
            mode: merge
            operations:
              - type: test_op
      YAML

      pipes = loader.load_pipes
      expect(pipes.keys).to contain_exactly(:pipe1, :pipe2)
    end

    it "returns empty hash when no pipes directory" do
      config.config_path = @tmpdir
      expect(loader.load_pipes).to eq({})
    end

    it "returns empty hash when no config path" do
      config.config_path = nil
      expect(loader.load_pipes).to eq({})
    end
  end

  describe "#setup_zeitwerk" do
    around do |example|
      Dir.mktmpdir do |dir|
        @tmpdir = dir
        example.run
      end
    end

    it "does nothing when no paths exist" do
      expect { loader.setup_zeitwerk([]) }.not_to raise_error
    end

    it "sets up zeitwerk for existing directories" do
      ops_dir = File.join(@tmpdir, "operations")
      FileUtils.mkdir_p(ops_dir)

      expect { loader.setup_zeitwerk([ops_dir]) }.not_to raise_error
    end
  end

  describe "operation options" do
    let(:test_operation) do
      Class.new(Brainpipe::Operation) do
        reads :input, String
        sets :output, String
      end
    end

    before do
      config.register_operation(:test_op, test_operation)
    end

    it "passes options to operation" do
      yaml_hash = {
        "type" => "test_op",
        "options" => {
          "format" => "json",
          "limit" => 100
        }
      }

      operation = loader.send(:build_operation, yaml_hash)
      expect(operation.options[:format]).to eq("json")
      expect(operation.options[:limit]).to eq(100)
    end

    it "passes timeout to operation via options" do
      yaml_hash = {
        "type" => "test_op",
        "timeout" => 15
      }

      operation = loader.send(:build_operation, yaml_hash)
      expect(operation.timeout).to eq(15)
    end

    it "merges timeout with other options" do
      yaml_hash = {
        "type" => "test_op",
        "timeout" => 15,
        "options" => {
          "format" => "json"
        }
      }

      operation = loader.send(:build_operation, yaml_hash)
      expect(operation.timeout).to eq(15)
      expect(operation.options[:format]).to eq("json")
    end
  end
end

RSpec.describe "Full integration" do
  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      example.run
    end
  end

  after do
    Brainpipe.reset!
  end

  it "loads config and pipes end-to-end" do
    config_dir = File.join(@tmpdir, "brainpipe")
    pipes_dir = File.join(config_dir, "pipes")
    FileUtils.mkdir_p(pipes_dir)

    File.write(File.join(config_dir, "config.yml"), <<~YAML)
      debug: true
      models:
        default:
          provider: openai
          model: gpt-4o
          capabilities:
            - text_to_text
    YAML

    test_op = Class.new(Brainpipe::Operation) do
      reads :input, String
      sets :output, String
      execute { |ns| ns.merge(output: ns[:input].upcase) }
    end

    File.write(File.join(pipes_dir, "test.yml"), <<~YAML)
      name: test_pipe
      stages:
        - name: transform
          mode: merge
          operations:
            - type: transformer
    YAML

    Brainpipe.configure do |c|
      c.config_path = config_dir
      c.register_operation(:transformer, test_op)
    end

    Brainpipe.load!

    expect(Brainpipe.configuration.debug).to be true
    expect(Brainpipe.model(:default).provider).to eq(:openai)

    pipe = Brainpipe.pipe(:test_pipe)
    result = pipe.call(input: "hello")
    expect(result[:output]).to eq("HELLO")
  end
end
