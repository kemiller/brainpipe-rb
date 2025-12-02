RSpec.describe "Type Flow" do
  describe "type preservation through prefix_schema" do
    it "Transform renames field with correct type in output schema" do
      transform = Brainpipe::Operations::Transform.new(
        options: { from: :input, to: :output }
      )

      prefix_schema = { input: { type: String, optional: false } }

      reads = transform.declared_reads(prefix_schema)
      sets = transform.declared_sets(prefix_schema)

      expect(reads[:input][:type]).to eq(String)
      expect(sets[:output][:type]).to eq(String)
    end

    it "chained transforms preserve type through chain" do
      transform1 = Brainpipe::Operations::Transform.new(
        options: { from: :a, to: :b }
      )
      transform2 = Brainpipe::Operations::Transform.new(
        options: { from: :b, to: :c }
      )

      initial_schema = { a: { type: Integer, optional: false } }

      schema_after_t1 = initial_schema.dup
      transform1.declared_deletes(initial_schema).each { |k| schema_after_t1.delete(k) }
      transform1.declared_sets(initial_schema).each { |k, v| schema_after_t1[k] = v }

      sets_t2 = transform2.declared_sets(schema_after_t1)

      expect(sets_t2[:c][:type]).to eq(Integer)
    end

    it "Merge enforces explicit target_type" do
      expect {
        Brainpipe::Operations::Merge.new(
          options: { sources: [:a, :b], target: :combined }
        )
      }.to raise_error(Brainpipe::ConfigurationError, /target_type/)
    end

    it "Merge uses explicit target_type in schema" do
      merge = Brainpipe::Operations::Merge.new(
        options: { sources: [:a, :b], target: :combined, target_type: String }
      )

      prefix_schema = { a: { type: Integer }, b: { type: Integer } }
      sets = merge.declared_sets(prefix_schema)

      expect(sets[:combined][:type]).to eq(String)
    end
  end

  describe "type conflict detection" do
    it "parallel ops setting same field with same type is OK" do
      op1 = Class.new(Brainpipe::Operation) do
        sets :result, String
      end.new

      op2 = Class.new(Brainpipe::Operation) do
        sets :result, String
      end.new

      stage = Brainpipe::Stage.new(
        name: :test,
        operations: [op1, op2]
      )

      expect { stage.validate_parallel_type_consistency!({}) }.not_to raise_error
    end

    it "parallel ops setting same field with different types raises TypeConflictError" do
      op1_class = Class.new(Brainpipe::Operation) do
        sets :result, String
      end
      stub_const("Op1", op1_class)

      op2_class = Class.new(Brainpipe::Operation) do
        sets :result, Integer
      end
      stub_const("Op2", op2_class)

      stage = Brainpipe::Stage.new(
        name: :test,
        operations: [Op1.new, Op2.new]
      )

      expect { stage.validate_parallel_type_consistency!({}) }
        .to raise_error(Brainpipe::TypeConflictError, /result.*String.*Integer/)
    end

    it "parallel ops setting different fields is OK" do
      op1 = Class.new(Brainpipe::Operation) do
        sets :result_a, String
      end.new

      op2 = Class.new(Brainpipe::Operation) do
        sets :result_b, Integer
      end.new

      stage = Brainpipe::Stage.new(
        name: :test,
        operations: [op1, op2]
      )

      expect { stage.validate_parallel_type_consistency!({}) }.not_to raise_error
    end

    it "ops setting same field without type is OK" do
      op1 = Class.new(Brainpipe::Operation) do
        sets :result
      end.new

      op2 = Class.new(Brainpipe::Operation) do
        sets :result
      end.new

      stage = Brainpipe::Stage.new(
        name: :test,
        operations: [op1, op2]
      )

      expect { stage.validate_parallel_type_consistency!({}) }.not_to raise_error
    end
  end

  describe "schema flow calculation" do
    it "computes prefix - deletes + sets correctly" do
      op_class = Class.new(Brainpipe::Operation) do
        reads :input, String
        sets :output, Integer
        deletes :temp
      end

      op = op_class.new
      stage = Brainpipe::Stage.new(
        name: :test,
        operations: [op]
      )

      prefix_schema = {
        input: { type: String, optional: false },
        temp: { type: String, optional: false },
        preserved: { type: Float, optional: false }
      }

      pipe = Brainpipe::Pipe.new(
        name: :test_pipe,
        stages: [stage]
      )

      output_schema = pipe.send(:compute_output_schema, prefix_schema, stage)

      expect(output_schema[:input]).to eq({ type: String, optional: false })
      expect(output_schema[:output]).to eq({ type: Integer, optional: false })
      expect(output_schema[:preserved]).to eq({ type: Float, optional: false })
      expect(output_schema).not_to have_key(:temp)
    end

    it "fields not touched by operation flow through unchanged" do
      op = Class.new(Brainpipe::Operation) do
        reads :input
        sets :output
      end.new

      stage = Brainpipe::Stage.new(
        name: :test,
        operations: [op]
      )

      prefix_schema = {
        input: { type: String, optional: false },
        passthrough1: { type: Integer, optional: false },
        passthrough2: { type: Float, optional: false }
      }

      pipe = Brainpipe::Pipe.new(
        name: :test_pipe,
        stages: [stage]
      )

      output_schema = pipe.send(:compute_output_schema, prefix_schema, stage)

      expect(output_schema[:passthrough1]).to eq({ type: Integer, optional: false })
      expect(output_schema[:passthrough2]).to eq({ type: Float, optional: false })
    end
  end
end
