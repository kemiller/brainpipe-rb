RSpec.describe Brainpipe::Observability::Debug do
  let(:output) { StringIO.new }
  subject(:debugger) { described_class.new(output: output) }

  describe "#pipe_start" do
    it "outputs pipe started message" do
      namespace = Brainpipe::Namespace.new(input: "value")
      debugger.pipe_start(:my_pipe, namespace)

      expect(output.string).to include("Pipe 'my_pipe' started")
    end

    it "includes input properties" do
      namespace = Brainpipe::Namespace.new(input: "value", count: 42)
      debugger.pipe_start(:my_pipe, namespace)

      expect(output.string).to include("Input:")
    end
  end

  describe "#pipe_end" do
    it "outputs pipe completed message with duration" do
      namespace = Brainpipe::Namespace.new(result: "done")
      debugger.pipe_end(:my_pipe, namespace, 150.5)

      expect(output.string).to include("Pipe 'my_pipe' completed")
      expect(output.string).to include("150.5ms")
    end

    it "formats duration in seconds for long operations" do
      namespace = Brainpipe::Namespace.new(result: "done")
      debugger.pipe_end(:my_pipe, namespace, 2500.0)

      expect(output.string).to include("2.5s")
    end

    it "includes output properties" do
      namespace = Brainpipe::Namespace.new(result: "done")
      debugger.pipe_end(:my_pipe, namespace, 100.0)

      expect(output.string).to include("Output:")
    end
  end

  describe "#pipe_error" do
    it "outputs pipe failed message" do
      error = RuntimeError.new("something went wrong")
      debugger.pipe_error(:my_pipe, error, 75.0)

      expect(output.string).to include("Pipe 'my_pipe' failed")
      expect(output.string).to include("75")
    end

    it "includes error class and message" do
      error = RuntimeError.new("something went wrong")
      debugger.pipe_error(:my_pipe, error, 75.0)

      expect(output.string).to include("RuntimeError")
      expect(output.string).to include("something went wrong")
    end
  end

  describe "#stage_start" do
    it "outputs stage started message" do
      debugger.stage_start(:process, 3)

      expect(output.string).to include("Stage 'process'")
      expect(output.string).to include("3 namespace(s)")
    end
  end

  describe "#stage_end" do
    it "outputs stage completed message with duration" do
      debugger.stage_end(:process, 50.25)

      expect(output.string).to include("Stage 'process' completed")
      expect(output.string).to include("50.25ms")
    end
  end

  describe "#stage_error" do
    it "outputs stage failed message" do
      error = ArgumentError.new("bad input")
      debugger.stage_error(:process, error, 30.0)

      expect(output.string).to include("Stage 'process' failed")
      expect(output.string).to include("ArgumentError")
    end
  end

  describe "#operation_start" do
    it "outputs operation started message with class name" do
      debugger.operation_start("MyOperation", [:input, :count])

      expect(output.string).to include("MyOperation started")
    end

    it "includes input keys" do
      debugger.operation_start("MyOperation", [:input, :count])

      expect(output.string).to include("Input keys:")
      expect(output.string).to include("input")
      expect(output.string).to include("count")
    end
  end

  describe "#operation_end" do
    it "outputs operation completed message with duration" do
      debugger.operation_end("MyOperation", 25.5, [:result, :status])

      expect(output.string).to include("MyOperation completed")
      expect(output.string).to include("25.5ms")
    end

    it "includes output keys" do
      debugger.operation_end("MyOperation", 25.5, [:result, :status])

      expect(output.string).to include("Output keys:")
      expect(output.string).to include("result")
      expect(output.string).to include("status")
    end
  end

  describe "#operation_error" do
    it "outputs operation failed message" do
      error = StandardError.new("operation failed")
      debugger.operation_error("MyOperation", error, 10.0)

      expect(output.string).to include("MyOperation failed")
      expect(output.string).to include("10")
    end

    it "includes error details" do
      error = StandardError.new("operation failed")
      debugger.operation_error("MyOperation", error, 10.0)

      expect(output.string).to include("StandardError")
      expect(output.string).to include("operation failed")
    end
  end

  describe "#namespace_state" do
    it "outputs labeled namespace state" do
      namespace = Brainpipe::Namespace.new(key: "value")
      debugger.namespace_state("Before", namespace)

      expect(output.string).to include("Before:")
    end
  end

  describe "truncation" do
    it "truncates long strings in output" do
      long_value = "x" * 300
      namespace = Brainpipe::Namespace.new(data: long_value)
      debugger.pipe_start(:my_pipe, namespace)

      expect(output.string).to include("...")
      expect(output.string.length).to be < 500
    end
  end

  describe "default output" do
    it "defaults to $stdout" do
      debug = described_class.new
      expect(debug.output).to eq($stdout)
    end
  end
end
