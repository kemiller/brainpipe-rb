RSpec.describe Brainpipe::Observability::MetricsCollector do
  subject(:collector) { described_class.new }

  describe "null implementation" do
    it "accepts operation_started without error" do
      expect {
        collector.operation_started(
          operation_class: Class.new,
          namespace: Brainpipe::Namespace.new,
          stage: :test_stage,
          pipe: :test_pipe
        )
      }.not_to raise_error
    end

    it "accepts operation_completed without error" do
      expect {
        collector.operation_completed(
          operation_class: Class.new,
          namespace: Brainpipe::Namespace.new,
          duration_ms: 100.5,
          stage: :test_stage,
          pipe: :test_pipe
        )
      }.not_to raise_error
    end

    it "accepts operation_failed without error" do
      expect {
        collector.operation_failed(
          operation_class: Class.new,
          namespace: nil,
          error: RuntimeError.new("test"),
          duration_ms: 50.0,
          stage: :test_stage,
          pipe: :test_pipe
        )
      }.not_to raise_error
    end

    it "accepts model_called without error" do
      expect {
        collector.model_called(
          model_config: double("ModelConfig"),
          input: "test input",
          output: "test output",
          tokens_in: 10,
          tokens_out: 20,
          duration_ms: 500.0
        )
      }.not_to raise_error
    end

    it "accepts stage_started without error" do
      expect {
        collector.stage_started(
          stage: :test_stage,
          namespace_count: 3,
          pipe: :test_pipe
        )
      }.not_to raise_error
    end

    it "accepts stage_completed without error" do
      expect {
        collector.stage_completed(
          stage: :test_stage,
          namespace_count: 3,
          duration_ms: 200.0,
          pipe: :test_pipe
        )
      }.not_to raise_error
    end

    it "accepts stage_failed without error" do
      expect {
        collector.stage_failed(
          stage: :test_stage,
          error: RuntimeError.new("stage error"),
          duration_ms: 150.0,
          pipe: :test_pipe
        )
      }.not_to raise_error
    end

    it "accepts pipe_started without error" do
      expect {
        collector.pipe_started(
          pipe: :test_pipe,
          input: Brainpipe::Namespace.new(foo: "bar")
        )
      }.not_to raise_error
    end

    it "accepts pipe_completed without error" do
      expect {
        collector.pipe_completed(
          pipe: :test_pipe,
          input: Brainpipe::Namespace.new(foo: "bar"),
          output: Brainpipe::Namespace.new(result: "done"),
          duration_ms: 1000.0,
          operations_count: 5
        )
      }.not_to raise_error
    end

    it "accepts pipe_failed without error" do
      expect {
        collector.pipe_failed(
          pipe: :test_pipe,
          error: RuntimeError.new("pipe error"),
          duration_ms: 800.0
        )
      }.not_to raise_error
    end
  end

  describe "subclass behavior" do
    it "allows subclasses to override methods" do
      events = []

      custom_collector = Class.new(described_class) do
        define_method(:operation_started) do |operation_class:, namespace:, stage:, pipe:|
          events << { type: :started, operation: operation_class }
        end

        define_method(:operation_completed) do |operation_class:, namespace:, duration_ms:, stage:, pipe:|
          events << { type: :completed, operation: operation_class, duration_ms: duration_ms }
        end
      end.new

      op_class = Class.new
      custom_collector.operation_started(
        operation_class: op_class,
        namespace: nil,
        stage: nil,
        pipe: nil
      )
      custom_collector.operation_completed(
        operation_class: op_class,
        namespace: nil,
        duration_ms: 42.5,
        stage: nil,
        pipe: nil
      )

      expect(events).to eq([
        { type: :started, operation: op_class },
        { type: :completed, operation: op_class, duration_ms: 42.5 }
      ])
    end
  end
end
