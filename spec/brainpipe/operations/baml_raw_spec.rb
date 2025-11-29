RSpec.describe Brainpipe::Operations::BamlRaw do
  before do
    Brainpipe::BamlAdapter.reset!
  end

  describe "#initialize" do
    it "raises ConfigurationError without function option" do
      allow(Brainpipe::BamlAdapter).to receive(:require_available!)

      expect { described_class.new(options: { image_extractor: :gemini_image }) }
        .to raise_error(Brainpipe::ConfigurationError, /requires 'function' option/)
    end

    it "raises ConfigurationError without image_extractor option" do
      allow(Brainpipe::BamlAdapter).to receive(:require_available!)

      expect { described_class.new(options: { function: :test }) }
        .to raise_error(Brainpipe::ConfigurationError, /requires 'image_extractor' option/)
    end

    it "raises ConfigurationError when BAML is not available" do
      expect { described_class.new(options: { function: :test, image_extractor: :gemini_image }) }
        .to raise_error(Brainpipe::ConfigurationError, /BAML is not available/)
    end
  end

  context "with mocked BAML" do
    let(:mock_baml_function) do
      mock = instance_double(Brainpipe::BamlFunction, name: :FixImage)
      allow(mock).to receive(:input_schema).and_return({
        img: { type: Brainpipe::Image, optional: false }
      })
      allow(mock).to receive(:output_schema).and_return({})
      mock
    end

    let(:mock_client) do
      client = double("BamlClient")
      allow(client).to receive(:respond_to?).with(:FixImage).and_return(true)
      allow(client).to receive(:respond_to?).with(:GenerateImage).and_return(true)
      client
    end

    let(:mock_request_builder) do
      builder = double("RequestBuilder")
      allow(builder).to receive(:respond_to?).with(:FixImage).and_return(true)
      allow(builder).to receive(:respond_to?).with(:GenerateImage).and_return(true)
      builder
    end

    let(:mock_raw_request) do
      request = double("RawRequest")
      allow(request).to receive(:url).and_return("https://api.example.com/v1/generate")
      allow(request).to receive(:headers).and_return({ "Content-Type" => "application/json", "Authorization" => "Bearer test" })
      allow(request).to receive(:body).and_return({ model: "gemini-2.0", contents: [] })
      allow(request).to receive(:parse).and_return({})
      request
    end

    before do
      allow(Brainpipe::BamlAdapter).to receive(:require_available!)
      allow(Brainpipe::BamlAdapter).to receive(:function).with(:FixImage).and_return(mock_baml_function)
      allow(Brainpipe::BamlAdapter).to receive(:function).with(:GenerateImage).and_return(mock_baml_function)
      allow(Brainpipe::BamlAdapter).to receive(:baml_client).and_return(mock_client)
      allow(Brainpipe::BamlAdapter).to receive(:to_baml_image).and_return(double("BamlImage"))
      allow(Brainpipe::BamlAdapter).to receive(:build_client_registry).and_return(nil)
      allow(mock_client).to receive(:request).and_return(mock_request_builder)
    end

    describe "#initialize" do
      it "accepts function and extractor options" do
        op = described_class.new(options: {
          function: :FixImage,
          image_extractor: :gemini_image
        })
        expect(op).to be_a(described_class)
      end

      it "resolves extractor from symbol name" do
        op = described_class.new(options: {
          function: :FixImage,
          image_extractor: :gemini_image
        })
        expect(op).to be_a(described_class)
      end

      it "resolves extractor from string name" do
        op = described_class.new(options: {
          function: :FixImage,
          image_extractor: "gemini_image"
        })
        expect(op).to be_a(described_class)
      end

      it "accepts module as extractor" do
        op = described_class.new(options: {
          function: :FixImage,
          image_extractor: Brainpipe::Extractors::GeminiImage
        })
        expect(op).to be_a(described_class)
      end

      it "accepts proc as extractor" do
        extractor = ->(response) { nil }
        op = described_class.new(options: {
          function: :FixImage,
          image_extractor: extractor
        })
        expect(op).to be_a(described_class)
      end

      it "raises error for unknown extractor" do
        expect {
          described_class.new(options: {
            function: :FixImage,
            image_extractor: :unknown_extractor
          })
        }.to raise_error(Brainpipe::ConfigurationError, /Unknown extractor/)
      end
    end

    describe "#declared_reads" do
      it "returns reads based on input mapping" do
        op = described_class.new(options: {
          function: :FixImage,
          image_extractor: :gemini_image,
          inputs: { img: :source_image, instructions: :fix_prompt }
        })

        reads = op.declared_reads
        expect(reads.keys).to contain_exactly(:source_image, :fix_prompt)
      end

      it "looks up types from prefix_schema" do
        op = described_class.new(options: {
          function: :FixImage,
          image_extractor: :gemini_image,
          inputs: { img: :source_image }
        })

        prefix_schema = { source_image: { type: Brainpipe::Image, optional: false } }
        reads = op.declared_reads(prefix_schema)

        expect(reads[:source_image][:type]).to eq(Brainpipe::Image)
      end
    end

    describe "#declared_sets" do
      it "returns output_field with Image type" do
        op = described_class.new(options: {
          function: :FixImage,
          image_extractor: :gemini_image,
          output_field: :result_image
        })

        sets = op.declared_sets
        expect(sets[:result_image]).to eq({ type: Brainpipe::Image, optional: false })
      end

      it "defaults output_field to :image" do
        op = described_class.new(options: {
          function: :FixImage,
          image_extractor: :gemini_image
        })

        sets = op.declared_sets
        expect(sets[:image]).to eq({ type: Brainpipe::Image, optional: false })
      end

      context "with BAML output schema" do
        let(:mock_baml_function_with_output) do
          mock = instance_double(Brainpipe::BamlFunction, name: :FixImage)
          allow(mock).to receive(:input_schema).and_return({})
          allow(mock).to receive(:output_schema).and_return({
            description: { type: String, optional: false }
          })
          mock
        end

        before do
          allow(Brainpipe::BamlAdapter).to receive(:function).with(:FixImage).and_return(mock_baml_function_with_output)
        end

        it "includes BAML output schema in declared_sets" do
          op = described_class.new(options: {
            function: :FixImage,
            image_extractor: :gemini_image
          })

          sets = op.declared_sets
          expect(sets[:image]).to eq({ type: Brainpipe::Image, optional: false })
          expect(sets[:description]).to eq({ type: String, optional: false })
        end
      end
    end

    describe "#declared_deletes" do
      it "returns empty array" do
        op = described_class.new(options: {
          function: :FixImage,
          image_extractor: :gemini_image
        })
        expect(op.declared_deletes).to eq([])
      end
    end

    describe "#required_model_capability" do
      it "requires image_edit capability" do
        op = described_class.new(options: {
          function: :FixImage,
          image_extractor: :gemini_image
        })
        expect(op.required_model_capability).to eq(:image_edit)
      end
    end

    describe "#create" do
      let(:gemini_response) do
        {
          "candidates" => [
            {
              "content" => {
                "parts" => [
                  {
                    "inlineData" => {
                      "mimeType" => "image/png",
                      "data" => "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
                    }
                  }
                ]
              }
            }
          ]
        }
      end

      let(:http_response) do
        response = double("Net::HTTPSuccess")
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(response).to receive(:body).and_return(gemini_response.to_json)
        response
      end

      before do
        allow(mock_request_builder).to receive(:FixImage).and_return(mock_raw_request)
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(http_response)
      end

      it "returns a callable" do
        op = described_class.new(options: {
          function: :FixImage,
          image_extractor: :gemini_image,
          inputs: { img: :source_image }
        })

        expect(op.create).to respond_to(:call)
      end

      it "extracts image from raw response using BAML parse" do
        op = described_class.new(options: {
          function: :FixImage,
          image_extractor: :gemini_image,
          inputs: { img: :source_image },
          output_field: :fixed_image
        })

        source_image = double("Image")

        namespaces = [Brainpipe::Namespace.new(source_image: source_image)]
        callable = op.create

        expect(mock_raw_request).to receive(:parse).with(gemini_response.to_json).and_return({})

        result = callable.call(namespaces)

        expect(result[0][:fixed_image]).to be_a(Brainpipe::Image)
        expect(result[0][:fixed_image].mime_type).to eq("image/png")
      end

      it "preserves other namespace fields" do
        op = described_class.new(options: {
          function: :FixImage,
          image_extractor: :gemini_image,
          inputs: { img: :source_image }
        })

        source_image = double("Image")

        namespaces = [Brainpipe::Namespace.new(source_image: source_image, other: "preserved")]
        callable = op.create

        result = callable.call(namespaces)

        expect(result[0][:other]).to eq("preserved")
        expect(result[0][:source_image]).to eq(source_image)
      end

      it "processes multiple namespaces" do
        op = described_class.new(options: {
          function: :FixImage,
          image_extractor: :gemini_image,
          inputs: { img: :source_image }
        })

        source_image1 = double("Image1")
        source_image2 = double("Image2")

        namespaces = [
          Brainpipe::Namespace.new(source_image: source_image1),
          Brainpipe::Namespace.new(source_image: source_image2)
        ]
        callable = op.create

        result = callable.call(namespaces)

        expect(result.size).to eq(2)
        expect(result[0][:image]).to be_a(Brainpipe::Image)
        expect(result[1][:image]).to be_a(Brainpipe::Image)
      end

      context "with BAML parsed output" do
        let(:mock_baml_function_with_output) do
          mock = instance_double(Brainpipe::BamlFunction, name: :FixImage)
          allow(mock).to receive(:input_schema).and_return({})
          allow(mock).to receive(:output_schema).and_return({
            description: { type: String, optional: false }
          })
          mock
        end

        before do
          allow(Brainpipe::BamlAdapter).to receive(:function).with(:FixImage).and_return(mock_baml_function_with_output)
          allow(mock_raw_request).to receive(:parse).and_return({ description: "Fixed image" })
        end

        it "merges BAML parsed output into namespace" do
          op = described_class.new(options: {
            function: :FixImage,
            image_extractor: :gemini_image,
            inputs: { img: :source_image }
          })

          source_image = double("Image")
          namespaces = [Brainpipe::Namespace.new(source_image: source_image)]
          callable = op.create

          result = callable.call(namespaces)

          expect(result[0][:image]).to be_a(Brainpipe::Image)
          expect(result[0][:description]).to eq("Fixed image")
        end
      end

      context "with custom output field" do
        it "sets result under configured field name" do
          op = described_class.new(options: {
            function: :FixImage,
            image_extractor: :gemini_image,
            inputs: { img: :source_image },
            output_field: :edited_image
          })

          source_image = double("Image")

          namespaces = [Brainpipe::Namespace.new(source_image: source_image)]
          callable = op.create

          result = callable.call(namespaces)

          expect(result[0][:edited_image]).to be_a(Brainpipe::Image)
          expect(result[0].key?(:image)).to be false
        end
      end

      context "with input mapping" do
        it "maps namespace fields to BAML input" do
          allow(mock_request_builder).to receive(:GenerateImage) do |**args|
            expect(args.keys).to contain_exactly(:prompt, :style)
            mock_raw_request
          end

          op = described_class.new(options: {
            function: :GenerateImage,
            image_extractor: :gemini_image,
            inputs: { prompt: :user_prompt, style: :image_style }
          })

          namespaces = [Brainpipe::Namespace.new(user_prompt: "a cat", image_style: "realistic")]
          callable = op.create

          result = callable.call(namespaces)

          expect(result[0][:image]).to be_a(Brainpipe::Image)
        end
      end
    end

    describe "error handling" do
      context "when HTTP request fails" do
        let(:failed_response) do
          response = double("Net::HTTPServerError")
          allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
          allow(response).to receive(:code).and_return("500")
          allow(response).to receive(:message).and_return("Internal Server Error")
          allow(response).to receive(:body).and_return('{"error": "Server Error"}')
          response
        end

        before do
          allow(mock_request_builder).to receive(:FixImage).and_return(mock_raw_request)
          allow_any_instance_of(Net::HTTP).to receive(:request).and_return(failed_response)
        end

        it "raises ExecutionError" do
          op = described_class.new(options: {
            function: :FixImage,
            image_extractor: :gemini_image,
            inputs: { img: :source_image }
          })

          source_image = double("Image")

          namespaces = [Brainpipe::Namespace.new(source_image: source_image)]
          callable = op.create

          expect { callable.call(namespaces) }
            .to raise_error(Brainpipe::ExecutionError, /HTTP request failed: 500/)
        end
      end

      context "when extractor returns nil" do
        let(:empty_response) do
          { "candidates" => [] }
        end

        let(:http_response) do
          response = double("Net::HTTPSuccess")
          allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
          allow(response).to receive(:body).and_return(empty_response.to_json)
          response
        end

        before do
          allow(mock_request_builder).to receive(:FixImage).and_return(mock_raw_request)
          allow_any_instance_of(Net::HTTP).to receive(:request).and_return(http_response)
        end

        it "raises ExecutionError" do
          op = described_class.new(options: {
            function: :FixImage,
            image_extractor: :gemini_image,
            inputs: { img: :source_image }
          })

          source_image = double("Image")

          namespaces = [Brainpipe::Namespace.new(source_image: source_image)]
          callable = op.create

          expect { callable.call(namespaces) }
            .to raise_error(Brainpipe::ExecutionError, /Extractor returned nil/)
        end
      end
    end

    describe "with model" do
      let(:model_config) do
        Brainpipe::ModelConfig.new(
          name: :gemini_image_edit,
          provider: :google_ai,
          model: "gemini-2.0-flash",
          capabilities: [:image_edit]
        )
      end

      it "passes model to operation" do
        op = described_class.new(
          model: model_config,
          options: {
            function: :FixImage,
            image_extractor: :gemini_image
          }
        )
        expect(op.model).to eq(model_config)
      end
    end
  end
end
