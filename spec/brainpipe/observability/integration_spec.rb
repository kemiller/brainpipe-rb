RSpec.describe "Observability Integration" do
  def create_operation(reads: {}, sets: {}, &block)
    op_class = Class.new(Brainpipe::Operation) do
      reads.each { |name, opts| reads(name, opts[:type], optional: opts[:optional] || false) }
      sets.each { |name, opts| sets(name, opts[:type], optional: opts[:optional] || false) }

      define_method(:_block) { block }

      execute do |ns|
        _block ? _block.call(ns) : ns.to_h
      end
    end
    op_class.new
  end

  def create_stage(name:, mode:, operations:)
    Brainpipe::Stage.new(
      name: name,
      mode: mode,
      operations: operations,
      merge_strategy: :last_in
    )
  end

  describe "MetricsCollector integration" do
    let(:events) { [] }
    let(:collector) do
      events_ref = events
      Class.new(Brainpipe::Observability::MetricsCollector) do
        define_method(:pipe_started) do |pipe:, input:|
          events_ref << { type: :pipe_started, pipe: pipe }
        end

        define_method(:pipe_completed) do |pipe:, input:, output:, duration_ms:, operations_count:|
          events_ref << { type: :pipe_completed, pipe: pipe, duration_ms: duration_ms, operations_count: operations_count }
        end

        define_method(:stage_started) do |stage:, namespace_count:, pipe:|
          events_ref << { type: :stage_started, stage: stage, pipe: pipe }
        end

        define_method(:stage_completed) do |stage:, namespace_count:, duration_ms:, pipe:|
          events_ref << { type: :stage_completed, stage: stage, duration_ms: duration_ms }
        end

        define_method(:operation_started) do |operation_class:, namespace:, stage:, pipe:|
          events_ref << { type: :operation_started, operation: operation_class, stage: stage }
        end

        define_method(:operation_completed) do |operation_class:, namespace:, duration_ms:, stage:, pipe:|
          events_ref << { type: :operation_completed, operation: operation_class, duration_ms: duration_ms }
        end
      end.new
    end

    it "emits pipe lifecycle events" do
      op = create_operation(reads: { input: {} }, sets: { output: {} }) do |ns|
        ns.merge(output: ns[:input].upcase)
      end
      stage = create_stage(name: :transform, mode: :merge, operations: [op])
      pipe = Brainpipe::Pipe.new(name: :test_pipe, stages: [stage])

      pipe.call({ input: "hello" }, metrics_collector: collector)

      pipe_events = events.select { |e| e[:type].to_s.start_with?("pipe_") }
      expect(pipe_events.map { |e| e[:type] }).to eq([:pipe_started, :pipe_completed])
      expect(pipe_events.last[:pipe]).to eq(:test_pipe)
      expect(pipe_events.last[:duration_ms]).to be_a(Numeric)
      expect(pipe_events.last[:operations_count]).to eq(1)
    end

    it "emits stage lifecycle events" do
      op = create_operation(reads: { input: {} }, sets: { output: {} }) do |ns|
        ns.merge(output: ns[:input].upcase)
      end
      stage = create_stage(name: :transform, mode: :merge, operations: [op])
      pipe = Brainpipe::Pipe.new(name: :test_pipe, stages: [stage])

      pipe.call({ input: "hello" }, metrics_collector: collector)

      stage_events = events.select { |e| e[:type].to_s.start_with?("stage_") }
      expect(stage_events.map { |e| e[:type] }).to eq([:stage_started, :stage_completed])
      expect(stage_events.first[:stage]).to eq(:transform)
      expect(stage_events.first[:pipe]).to eq(:test_pipe)
    end

    it "emits operation lifecycle events" do
      op = create_operation(reads: { input: {} }, sets: { output: {} }) do |ns|
        ns.merge(output: ns[:input].upcase)
      end
      stage = create_stage(name: :transform, mode: :merge, operations: [op])
      pipe = Brainpipe::Pipe.new(name: :test_pipe, stages: [stage])

      pipe.call({ input: "hello" }, metrics_collector: collector)

      op_events = events.select { |e| e[:type].to_s.start_with?("operation_") }
      expect(op_events.map { |e| e[:type] }).to eq([:operation_started, :operation_completed])
      expect(op_events.first[:stage]).to eq(:transform)
      expect(op_events.last[:duration_ms]).to be_a(Numeric)
    end

    it "emits events in correct order" do
      op = create_operation(reads: { input: {} }, sets: { output: {} }) do |ns|
        ns.merge(output: ns[:input].upcase)
      end
      stage = create_stage(name: :transform, mode: :merge, operations: [op])
      pipe = Brainpipe::Pipe.new(name: :test_pipe, stages: [stage])

      pipe.call({ input: "hello" }, metrics_collector: collector)

      expected_order = [
        :pipe_started,
        :stage_started,
        :operation_started,
        :operation_completed,
        :stage_completed,
        :pipe_completed
      ]
      expect(events.map { |e| e[:type] }).to eq(expected_order)
    end

    it "tracks multiple operations per stage" do
      op1 = create_operation(sets: { a: {} }) { |ns| ns.merge(a: 1) }
      op2 = create_operation(sets: { b: {} }) { |ns| ns.merge(b: 2) }
      stage = create_stage(name: :multi, mode: :merge, operations: [op1, op2])
      pipe = Brainpipe::Pipe.new(name: :test_pipe, stages: [stage])

      pipe.call({}, metrics_collector: collector)

      op_events = events.select { |e| e[:type].to_s.start_with?("operation_") }
      expect(op_events.count { |e| e[:type] == :operation_started }).to eq(2)
      expect(op_events.count { |e| e[:type] == :operation_completed }).to eq(2)
    end

    it "tracks multiple stages" do
      op1 = create_operation(sets: { a: {} }) { |ns| ns.merge(a: 1) }
      op2 = create_operation(reads: { a: {} }, sets: { b: {} }) { |ns| ns.merge(b: 2) }
      stage1 = create_stage(name: :first, mode: :merge, operations: [op1])
      stage2 = create_stage(name: :second, mode: :merge, operations: [op2])
      pipe = Brainpipe::Pipe.new(name: :test_pipe, stages: [stage1, stage2])

      pipe.call({}, metrics_collector: collector)

      stage_events = events.select { |e| e[:type].to_s.start_with?("stage_") }
      stage_names = stage_events.select { |e| e[:type] == :stage_started }.map { |e| e[:stage] }
      expect(stage_names).to eq([:first, :second])
    end
  end

  describe "Debug integration" do
    it "outputs debug information when debug is enabled" do
      output = StringIO.new
      debugger = Brainpipe::Observability::Debug.new(output: output)

      op = create_operation(reads: { input: {} }, sets: { output: {} }) do |ns|
        ns.merge(output: ns[:input].upcase)
      end
      stage = create_stage(name: :transform, mode: :merge, operations: [op])
      pipe = Brainpipe::Pipe.new(name: :test_pipe, stages: [stage])

      pipe.call({ input: "hello" }, debugger: debugger)

      expect(output.string).to include("Pipe 'test_pipe' started")
      expect(output.string).to include("Stage 'transform'")
      expect(output.string).to include("completed")
    end

    it "uses debug flag from pipe initialization" do
      op = create_operation(reads: { input: {} }, sets: { output: {} }) do |ns|
        ns.merge(output: ns[:input].upcase)
      end
      stage = create_stage(name: :transform, mode: :merge, operations: [op])
      pipe = Brainpipe::Pipe.new(name: :test_pipe, stages: [stage], debug: true)

      output = StringIO.new
      original_stdout = $stdout
      begin
        $stdout = output
        pipe.call({ input: "hello" })
      ensure
        $stdout = original_stdout
      end

      expect(output.string).to include("Pipe 'test_pipe'")
    end
  end
end
