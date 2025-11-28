RSpec.describe Brainpipe::Operation do
  describe "class-level DSL" do
    describe ".reads" do
      it "declares a property to read" do
        op_class = Class.new(described_class) do
          reads :input
        end

        instance = op_class.new
        expect(instance.declared_reads).to eq({ input: { type: nil, optional: false } })
      end

      it "declares a property with a type" do
        op_class = Class.new(described_class) do
          reads :name, String
        end

        instance = op_class.new
        expect(instance.declared_reads[:name][:type]).to eq(String)
      end

      it "declares an optional property" do
        op_class = Class.new(described_class) do
          reads :email, String, optional: true
        end

        instance = op_class.new
        expect(instance.declared_reads[:email][:optional]).to be true
      end

      it "supports multiple reads declarations" do
        op_class = Class.new(described_class) do
          reads :name, String
          reads :age, Integer
        end

        instance = op_class.new
        expect(instance.declared_reads.keys).to eq([:name, :age])
      end

      it "converts string keys to symbols" do
        op_class = Class.new(described_class) do
          reads "name", String
        end

        instance = op_class.new
        expect(instance.declared_reads.keys).to eq([:name])
      end
    end

    describe ".sets" do
      it "declares a property to set" do
        op_class = Class.new(described_class) do
          sets :output
        end

        instance = op_class.new
        expect(instance.declared_sets).to eq({ output: { type: nil, optional: false } })
      end

      it "declares a property with a type" do
        op_class = Class.new(described_class) do
          sets :result, Hash
        end

        instance = op_class.new
        expect(instance.declared_sets[:result][:type]).to eq(Hash)
      end

      it "declares an optional set" do
        op_class = Class.new(described_class) do
          sets :metadata, Hash, optional: true
        end

        instance = op_class.new
        expect(instance.declared_sets[:metadata][:optional]).to be true
      end
    end

    describe ".deletes" do
      it "declares a property to delete" do
        op_class = Class.new(described_class) do
          deletes :temp
        end

        instance = op_class.new
        expect(instance.declared_deletes).to eq([:temp])
      end

      it "supports multiple deletes" do
        op_class = Class.new(described_class) do
          deletes :temp1
          deletes :temp2
        end

        instance = op_class.new
        expect(instance.declared_deletes).to eq([:temp1, :temp2])
      end
    end

    describe ".requires_model" do
      it "declares a required model capability" do
        op_class = Class.new(described_class) do
          requires_model :text_to_text
        end

        instance = op_class.new
        expect(instance.required_model_capability).to eq(:text_to_text)
      end

      it "converts string to symbol" do
        op_class = Class.new(described_class) do
          requires_model "image_to_text"
        end

        instance = op_class.new
        expect(instance.required_model_capability).to eq(:image_to_text)
      end
    end

    describe ".ignore_errors" do
      it "accepts a boolean value" do
        op_class = Class.new(described_class) do
          ignore_errors true
        end

        instance = op_class.new
        expect(instance.error_handler).to be true
      end

      it "accepts a block" do
        handler = ->(error) { error.is_a?(RuntimeError) }
        op_class = Class.new(described_class) do
          ignore_errors(&handler)
        end

        instance = op_class.new
        expect(instance.error_handler).to eq(handler)
      end
    end

    describe ".execute" do
      it "stores a block for per-namespace execution" do
        op_class = Class.new(described_class) do
          execute do |ns|
            { processed: true }
          end
        end

        expect(op_class._execute_block).to be_a(Proc)
      end
    end
  end

  describe "instance methods" do
    describe "#initialize" do
      it "accepts a model parameter" do
        model = double("model")
        instance = described_class.new(model: model)
        expect(instance.model).to eq(model)
      end

      it "accepts options" do
        instance = described_class.new(options: { key: "value" })
        expect(instance.options).to eq({ key: "value" })
      end

      it "freezes the options" do
        instance = described_class.new(options: { key: "value" })
        expect(instance.options).to be_frozen
      end

      it "defaults model to nil" do
        instance = described_class.new
        expect(instance.model).to be_nil
      end

      it "defaults options to empty hash" do
        instance = described_class.new
        expect(instance.options).to eq({})
      end
    end

    describe "#declared_reads" do
      it "returns a copy of the class reads" do
        op_class = Class.new(described_class) do
          reads :input
        end

        instance = op_class.new
        reads = instance.declared_reads
        reads[:modified] = true

        expect(instance.declared_reads).not_to have_key(:modified)
      end
    end

    describe "#declared_sets" do
      it "returns a copy of the class sets" do
        op_class = Class.new(described_class) do
          sets :output
        end

        instance = op_class.new
        sets = instance.declared_sets
        sets[:modified] = true

        expect(instance.declared_sets).not_to have_key(:modified)
      end
    end

    describe "#declared_deletes" do
      it "returns a copy of the class deletes" do
        op_class = Class.new(described_class) do
          deletes :temp
        end

        instance = op_class.new
        deletes = instance.declared_deletes
        deletes << :modified

        expect(instance.declared_deletes).not_to include(:modified)
      end
    end

    describe "#create" do
      context "with execute block" do
        it "returns a callable that processes each namespace" do
          op_class = Class.new(described_class) do
            execute do |ns|
              { processed: ns[:value] * 2 }
            end
          end

          instance = op_class.new
          callable = instance.create
          namespaces = [Brainpipe::Namespace.new(value: 5)]

          result = callable.call(namespaces)

          expect(result.length).to eq(1)
          expect(result[0][:processed]).to eq(10)
        end

        it "merges returned hash into namespace" do
          op_class = Class.new(described_class) do
            execute do |ns|
              { new_key: "added" }
            end
          end

          instance = op_class.new
          callable = instance.create
          namespaces = [Brainpipe::Namespace.new(existing: "kept")]

          result = callable.call(namespaces)

          expect(result[0][:existing]).to eq("kept")
          expect(result[0][:new_key]).to eq("added")
        end

        it "allows returning a Namespace directly" do
          op_class = Class.new(described_class) do
            execute do |ns|
              Brainpipe::Namespace.new(replaced: true)
            end
          end

          instance = op_class.new
          callable = instance.create
          namespaces = [Brainpipe::Namespace.new(original: true)]

          result = callable.call(namespaces)

          expect(result[0][:replaced]).to be true
          expect(result[0][:original]).to be_nil
        end

        it "handles nil return by keeping original namespace" do
          op_class = Class.new(described_class) do
            execute do |ns|
              nil
            end
          end

          instance = op_class.new
          callable = instance.create
          namespaces = [Brainpipe::Namespace.new(kept: true)]

          result = callable.call(namespaces)

          expect(result[0][:kept]).to be true
        end

        it "processes multiple namespaces" do
          op_class = Class.new(described_class) do
            execute do |ns|
              { doubled: ns[:value] * 2 }
            end
          end

          instance = op_class.new
          callable = instance.create
          namespaces = [
            Brainpipe::Namespace.new(value: 1),
            Brainpipe::Namespace.new(value: 2),
            Brainpipe::Namespace.new(value: 3)
          ]

          result = callable.call(namespaces)

          expect(result.map { |ns| ns[:doubled] }).to eq([2, 4, 6])
        end
      end

      context "without execute block (custom call)" do
        it "delegates to #call method" do
          op_class = Class.new(described_class) do
            def call(namespaces)
              namespaces.map { |ns| ns.merge(custom: true) }
            end
          end

          instance = op_class.new
          callable = instance.create
          namespaces = [Brainpipe::Namespace.new(original: true)]

          result = callable.call(namespaces)

          expect(result[0][:custom]).to be true
          expect(result[0][:original]).to be true
        end

        it "provides full array control" do
          op_class = Class.new(described_class) do
            def call(namespaces)
              merged = namespaces.reduce({}) { |acc, ns| acc.merge(ns.to_h) }
              [Brainpipe::Namespace.new(merged)]
            end
          end

          instance = op_class.new
          callable = instance.create
          namespaces = [
            Brainpipe::Namespace.new(a: 1),
            Brainpipe::Namespace.new(b: 2)
          ]

          result = callable.call(namespaces)

          expect(result.length).to eq(1)
          expect(result[0][:a]).to eq(1)
          expect(result[0][:b]).to eq(2)
        end
      end
    end

    describe "#call" do
      it "returns namespaces unchanged by default" do
        instance = described_class.new
        namespaces = [Brainpipe::Namespace.new(value: 1)]

        result = instance.call(namespaces)

        expect(result).to eq(namespaces)
      end
    end
  end

  describe "inheritance" do
    it "does not share declarations between subclasses" do
      parent = Class.new(described_class) do
        reads :parent_input
        sets :parent_output
      end

      child1 = Class.new(parent) do
        reads :child1_input
      end

      child2 = Class.new(parent) do
        reads :child2_input
      end

      expect(child1.new.declared_reads.keys).to eq([:child1_input])
      expect(child2.new.declared_reads.keys).to eq([:child2_input])
    end
  end

  describe "access to operation instance from execute block" do
    it "can access model" do
      model = double("model", generate: "result")
      op_class = Class.new(described_class) do
        execute do |ns|
          { result: model.generate }
        end
      end

      instance = op_class.new(model: model)
      callable = instance.create
      result = callable.call([Brainpipe::Namespace.new])

      expect(result[0][:result]).to eq("result")
    end

    it "can access options" do
      op_class = Class.new(described_class) do
        execute do |ns|
          { multiplier: options[:multiplier], result: ns[:value] * options[:multiplier] }
        end
      end

      instance = op_class.new(options: { multiplier: 3 })
      callable = instance.create
      result = callable.call([Brainpipe::Namespace.new(value: 5)])

      expect(result[0][:result]).to eq(15)
    end
  end
end
