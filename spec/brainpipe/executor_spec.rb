RSpec.describe Brainpipe::Executor do
  let(:namespace) { Brainpipe::Namespace.new(input: "value") }
  let(:namespaces) { [namespace] }

  def create_operation(reads: {}, sets: {}, deletes: [], error_handler: nil)
    op_class = Class.new(Brainpipe::Operation) do
      reads.each { |name, opts| reads(name, opts[:type], optional: opts[:optional] || false) }
      sets.each { |name, opts| sets(name, opts[:type], optional: opts[:optional] || false) }
      deletes.each { |name| deletes(name) }
      ignore_errors(error_handler) if error_handler
    end
    op_class.new
  end

  describe "#initialize" do
    it "stores the callable" do
      callable = ->(ns) { ns }
      operation = create_operation
      executor = described_class.new(callable, operation: operation)

      expect(executor.callable).to eq(callable)
    end

    it "stores the operation" do
      callable = ->(ns) { ns }
      operation = create_operation
      executor = described_class.new(callable, operation: operation)

      expect(executor.operation).to eq(operation)
    end

    it "stores the debug flag" do
      callable = ->(ns) { ns }
      operation = create_operation
      executor = described_class.new(callable, operation: operation, debug: true)

      expect(executor.debug).to be true
    end

    it "defaults debug to false" do
      callable = ->(ns) { ns }
      operation = create_operation
      executor = described_class.new(callable, operation: operation)

      expect(executor.debug).to be false
    end
  end

  describe "#call" do
    context "basic execution" do
      it "calls the callable with namespaces" do
        callable = ->(ns) { ns.map { |n| n.merge(processed: true) } }
        operation = create_operation
        executor = described_class.new(callable, operation: operation)

        result = executor.call(namespaces)

        expect(result[0][:processed]).to be true
      end

      it "returns the result from the callable" do
        callable = ->(ns) { ns.map { |n| n.merge(output: "result") } }
        operation = create_operation
        executor = described_class.new(callable, operation: operation)

        result = executor.call(namespaces)

        expect(result[0][:output]).to eq("result")
      end
    end

    context "read validation" do
      it "passes when declared reads exist" do
        callable = ->(ns) { ns }
        operation = create_operation(reads: { input: {} })
        executor = described_class.new(callable, operation: operation)

        expect { executor.call(namespaces) }.not_to raise_error
      end

      it "raises PropertyNotFoundError when declared read is missing" do
        callable = ->(ns) { ns }
        operation = create_operation(reads: { missing_key: {} })
        executor = described_class.new(callable, operation: operation)

        expect { executor.call(namespaces) }.to raise_error(
          Brainpipe::PropertyNotFoundError,
          /expected to read 'missing_key' but it was not found/
        )
      end

      it "skips validation for optional reads that are missing" do
        callable = ->(ns) { ns }
        operation = create_operation(reads: { optional_key: { optional: true } })
        executor = described_class.new(callable, operation: operation)

        expect { executor.call(namespaces) }.not_to raise_error
      end

      it "validates type when present" do
        callable = ->(ns) { ns }
        operation = create_operation(reads: { input: { type: Integer } })
        executor = described_class.new(callable, operation: operation)

        expect { executor.call(namespaces) }.to raise_error(
          Brainpipe::TypeMismatchError
        )
      end

      it "passes type validation when type matches" do
        callable = ->(ns) { ns }
        operation = create_operation(reads: { input: { type: String } })
        executor = described_class.new(callable, operation: operation)

        expect { executor.call(namespaces) }.not_to raise_error
      end

      it "validates reads for each namespace" do
        ns1 = Brainpipe::Namespace.new(input: "a")
        ns2 = Brainpipe::Namespace.new(other: "b")
        callable = ->(ns) { ns }
        operation = create_operation(reads: { input: {} })
        executor = described_class.new(callable, operation: operation)

        expect { executor.call([ns1, ns2]) }.to raise_error(
          Brainpipe::PropertyNotFoundError
        )
      end
    end

    context "set validation" do
      it "passes when declared sets appear in output" do
        callable = ->(ns) { ns.map { |n| n.merge(output: "value") } }
        operation = create_operation(sets: { output: {} })
        executor = described_class.new(callable, operation: operation)

        expect { executor.call(namespaces) }.not_to raise_error
      end

      it "raises UnexpectedPropertyError when declared set is missing from output" do
        callable = ->(ns) { ns }
        operation = create_operation(sets: { missing_output: {} })
        executor = described_class.new(callable, operation: operation)

        expect { executor.call(namespaces) }.to raise_error(
          Brainpipe::UnexpectedPropertyError,
          /declared it would set 'missing_output' but it was not found/
        )
      end

      it "skips validation for optional sets that are missing" do
        callable = ->(ns) { ns }
        operation = create_operation(sets: { optional_output: { optional: true } })
        executor = described_class.new(callable, operation: operation)

        expect { executor.call(namespaces) }.not_to raise_error
      end

      it "validates set type when present" do
        callable = ->(ns) { ns.map { |n| n.merge(output: "string") } }
        operation = create_operation(sets: { output: { type: Integer } })
        executor = described_class.new(callable, operation: operation)

        expect { executor.call(namespaces) }.to raise_error(
          Brainpipe::TypeMismatchError
        )
      end

      it "passes set type validation when type matches" do
        callable = ->(ns) { ns.map { |n| n.merge(output: 42) } }
        operation = create_operation(sets: { output: { type: Integer } })
        executor = described_class.new(callable, operation: operation)

        expect { executor.call(namespaces) }.not_to raise_error
      end
    end

    context "delete validation" do
      it "passes when declared deletes are removed" do
        ns = Brainpipe::Namespace.new(to_delete: "value", keep: "kept")
        callable = ->(namespaces) { namespaces.map { |n| n.delete(:to_delete) } }
        operation = create_operation(deletes: [:to_delete])
        executor = described_class.new(callable, operation: operation)

        expect { executor.call([ns]) }.not_to raise_error
      end

      it "raises UnexpectedDeletionError when declared delete still exists" do
        ns = Brainpipe::Namespace.new(to_delete: "value")
        callable = ->(namespaces) { namespaces }
        operation = create_operation(deletes: [:to_delete])
        executor = described_class.new(callable, operation: operation)

        expect { executor.call([ns]) }.to raise_error(
          Brainpipe::UnexpectedDeletionError,
          /declared it would delete 'to_delete' but it still exists/
        )
      end

      it "validates deletes for each output namespace" do
        ns = Brainpipe::Namespace.new(to_delete: "value")
        callable = ->(namespaces) do
          [
            namespaces[0].delete(:to_delete),
            namespaces[0]
          ]
        end
        operation = create_operation(deletes: [:to_delete])
        executor = described_class.new(callable, operation: operation)

        expect { executor.call([ns, ns]) }.to raise_error(
          Brainpipe::UnexpectedDeletionError
        )
      end
    end

    context "output count validation" do
      it "passes when output count matches input count" do
        callable = ->(ns) { ns.map { |n| n.merge(processed: true) } }
        operation = create_operation
        executor = described_class.new(callable, operation: operation)

        expect { executor.call(namespaces) }.not_to raise_error
      end

      it "raises OutputCountMismatchError when output count differs" do
        callable = ->(ns) { [] }
        operation = create_operation
        executor = described_class.new(callable, operation: operation)

        expect { executor.call(namespaces) }.to raise_error(
          Brainpipe::OutputCountMismatchError,
          /returned 0 namespaces but received 1/
        )
      end

      it "raises OutputCountMismatchError when output has more namespaces" do
        callable = ->(ns) { ns + ns }
        operation = create_operation
        executor = described_class.new(callable, operation: operation)

        expect { executor.call(namespaces) }.to raise_error(
          Brainpipe::OutputCountMismatchError,
          /returned 2 namespaces but received 1/
        )
      end
    end

    context "error handling" do
      it "raises errors by default" do
        callable = ->(_) { raise RuntimeError, "boom" }
        operation = create_operation
        executor = described_class.new(callable, operation: operation)

        expect { executor.call(namespaces) }.to raise_error(RuntimeError, "boom")
      end

      context "with boolean true error handler" do
        it "suppresses all errors and returns empty array" do
          callable = ->(_) { raise RuntimeError, "boom" }
          operation = create_operation(error_handler: true)
          executor = described_class.new(callable, operation: operation)

          result = executor.call(namespaces)

          expect(result).to eq([])
        end
      end

      context "with proc error handler" do
        it "suppresses error when proc returns true" do
          callable = ->(_) { raise RuntimeError, "boom" }
          handler = ->(e) { e.is_a?(RuntimeError) }
          operation = create_operation(error_handler: handler)
          executor = described_class.new(callable, operation: operation)

          result = executor.call(namespaces)

          expect(result).to eq([])
        end

        it "re-raises error when proc returns false" do
          callable = ->(_) { raise ArgumentError, "bad arg" }
          handler = ->(e) { e.is_a?(RuntimeError) }
          operation = create_operation(error_handler: handler)
          executor = described_class.new(callable, operation: operation)

          expect { executor.call(namespaces) }.to raise_error(ArgumentError, "bad arg")
        end

        it "passes the error to the handler proc" do
          received_error = nil
          callable = ->(_) { raise RuntimeError, "test error" }
          handler = ->(e) { received_error = e; true }
          operation = create_operation(error_handler: handler)
          executor = described_class.new(callable, operation: operation)

          executor.call(namespaces)

          expect(received_error).to be_a(RuntimeError)
          expect(received_error.message).to eq("test error")
        end
      end
    end

    context "multiple namespaces" do
      it "validates reads for all namespaces before execution" do
        ns1 = Brainpipe::Namespace.new(required: "a")
        ns2 = Brainpipe::Namespace.new(other: "b")
        call_count = 0
        callable = ->(ns) { call_count += 1; ns }
        operation = create_operation(reads: { required: {} })
        executor = described_class.new(callable, operation: operation)

        expect { executor.call([ns1, ns2]) }.to raise_error(Brainpipe::PropertyNotFoundError)
        expect(call_count).to eq(0)
      end

      it "validates sets for all output namespaces" do
        callable = ->(ns) do
          [
            ns[0].merge(output: "present"),
            ns[1]
          ]
        end
        operation = create_operation(sets: { output: {} })
        executor = described_class.new(callable, operation: operation)

        expect { executor.call([namespace, namespace]) }.to raise_error(
          Brainpipe::UnexpectedPropertyError
        )
      end
    end
  end

  describe "error messages" do
    it "includes operation name in PropertyNotFoundError" do
      op_class = Class.new(Brainpipe::Operation) do
        reads :missing
      end

      stub_const("MyCustomOperation", op_class)
      operation = MyCustomOperation.new
      callable = ->(ns) { ns }
      executor = described_class.new(callable, operation: operation)

      expect { executor.call(namespaces) }.to raise_error(
        Brainpipe::PropertyNotFoundError,
        /MyCustomOperation/
      )
    end

    it "includes operation name in UnexpectedPropertyError" do
      op_class = Class.new(Brainpipe::Operation) do
        sets :missing_output
      end

      stub_const("AnotherOperation", op_class)
      operation = AnotherOperation.new
      callable = ->(ns) { ns }
      executor = described_class.new(callable, operation: operation)

      expect { executor.call(namespaces) }.to raise_error(
        Brainpipe::UnexpectedPropertyError,
        /AnotherOperation/
      )
    end

    it "handles anonymous operations gracefully" do
      operation = create_operation(reads: { missing: {} })
      callable = ->(ns) { ns }
      executor = described_class.new(callable, operation: operation)

      expect { executor.call(namespaces) }.to raise_error(
        Brainpipe::PropertyNotFoundError,
        /Anonymous Operation/
      )
    end
  end

  describe "integration with Operation#create" do
    it "works with operation-generated callables" do
      op_class = Class.new(Brainpipe::Operation) do
        reads :input, String
        sets :output, String

        execute do |ns|
          { output: ns[:input].upcase }
        end
      end

      operation = op_class.new
      callable = operation.create
      executor = described_class.new(callable, operation: operation)

      result = executor.call([Brainpipe::Namespace.new(input: "hello")])

      expect(result[0][:output]).to eq("HELLO")
    end
  end

  describe "timeout behavior" do
    it "stores timeout from initialization" do
      callable = ->(ns) { ns }
      operation = create_operation
      executor = described_class.new(callable, operation: operation, timeout: 5)

      expect(executor.timeout).to eq(5)
    end

    it "defaults timeout to nil" do
      callable = ->(ns) { ns }
      operation = create_operation
      executor = described_class.new(callable, operation: operation)

      expect(executor.timeout).to be_nil
    end

    it "raises TimeoutError when operation times out" do
      callable = ->(ns) do
        sleep(0.5)
        ns
      end
      operation = create_operation
      executor = described_class.new(callable, operation: operation, timeout: 0.1)

      expect { executor.call(namespaces) }
        .to raise_error(Brainpipe::TimeoutError, /timed out after 0.1 seconds/)
    end

    it "completes when execution is within timeout" do
      callable = ->(ns) { ns.map { |n| n.merge(result: "done") } }
      operation = create_operation
      executor = described_class.new(callable, operation: operation, timeout: 5)

      result = executor.call(namespaces)

      expect(result[0][:result]).to eq("done")
    end

    it "includes operation name in timeout error" do
      op_class = Class.new(Brainpipe::Operation) do
      end
      stub_const("SlowOperation", op_class)

      callable = ->(ns) do
        sleep(0.5)
        ns
      end
      operation = SlowOperation.new
      executor = described_class.new(callable, operation: operation, timeout: 0.1)

      expect { executor.call(namespaces) }
        .to raise_error(Brainpipe::TimeoutError, /SlowOperation/)
    end
  end
end
