RSpec.describe Brainpipe::ProviderAdapters::GoogleAI do
  let(:adapter) { described_class.new }

  let(:model_config) do
    Brainpipe::ModelConfig.new(
      name: :gemini,
      provider: :google_ai,
      model: "gemini-2.0-flash",
      capabilities: [:text_to_text],
      options: { api_key: "test-api-key" }
    )
  end

  describe "#call" do
    let(:mock_response) do
      {
        "candidates" => [
          {
            "content" => {
              "parts" => [
                { "text" => "Hello, world!" }
              ]
            }
          }
        ]
      }
    end

    before do
      stub_request(:post, %r{https://generativelanguage\.googleapis\.com/v1beta/models/gemini-2\.0-flash:generateContent})
        .to_return(status: 200, body: JSON.generate(mock_response), headers: { "Content-Type" => "application/json" })
    end

    it "makes request to Google AI API with api key in URL" do
      adapter.call(prompt: "Hello", model_config: model_config)

      expect(WebMock).to have_requested(:post, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=test-api-key")
    end

    it "sends prompt as text part" do
      adapter.call(prompt: "Hello", model_config: model_config)

      expect(WebMock).to have_requested(:post, %r{generateContent})
        .with { |req|
          body = JSON.parse(req.body)
          body["contents"][0]["parts"] == [{ "text" => "Hello" }]
        }
    end

    it "returns parsed response" do
      result = adapter.call(prompt: "Hello", model_config: model_config)
      expect(result).to eq(mock_response)
    end

    context "with images" do
      let(:image) { Brainpipe::Image.from_base64("aGVsbG8=", mime_type: "image/png") }

      it "sends images as inlineData parts" do
        adapter.call(prompt: "What's in this image?", model_config: model_config, images: [image])

        expect(WebMock).to have_requested(:post, %r{generateContent})
          .with { |req|
            body = JSON.parse(req.body)
            parts = body["contents"][0]["parts"]
            parts[0]["inlineData"]["mimeType"] == "image/png" &&
              parts[0]["inlineData"]["data"] == "aGVsbG8=" &&
              parts[1] == { "text" => "What's in this image?" }
          }
      end
    end

    context "with model options" do
      let(:model_config_with_options) do
        Brainpipe::ModelConfig.new(
          name: :gemini,
          provider: :google_ai,
          model: "gemini-2.0-flash",
          capabilities: [:text_to_text],
          options: { api_key: "test-api-key", temperature: 0.7, max_tokens: 1000 }
        )
      end

      it "includes generation config in request" do
        adapter.call(prompt: "Hello", model_config: model_config_with_options)

        expect(WebMock).to have_requested(:post, %r{generateContent})
          .with { |req|
            body = JSON.parse(req.body)
            body["generationConfig"]["temperature"] == 0.7 &&
              body["generationConfig"]["maxOutputTokens"] == 1000
          }
      end
    end

    context "with nested generation_config option" do
      let(:model_config_with_nested) do
        Brainpipe::ModelConfig.new(
          name: :gemini,
          provider: :google_ai,
          model: "gemini-2.0-flash",
          capabilities: [:text_to_text],
          options: {
            api_key: "test-api-key",
            generation_config: {
              "responseMimeType" => "image/png"
            }
          }
        )
      end

      it "merges nested generation_config into request" do
        adapter.call(prompt: "Hello", model_config: model_config_with_nested)

        expect(WebMock).to have_requested(:post, %r{generateContent})
          .with { |req|
            body = JSON.parse(req.body)
            body["generationConfig"]["responseMimeType"] == "image/png"
          }
      end
    end

    context "without api_key" do
      let(:model_config_no_key) do
        Brainpipe::ModelConfig.new(
          name: :gemini,
          provider: :google_ai,
          model: "gemini-2.0-flash",
          capabilities: [:text_to_text]
        )
      end

      it "raises ConfigurationError" do
        expect {
          adapter.call(prompt: "Hello", model_config: model_config_no_key)
        }.to raise_error(Brainpipe::ConfigurationError, /API key required/)
      end
    end

    context "when API returns error" do
      before do
        stub_request(:post, %r{generateContent})
          .to_return(status: 401, body: '{"error": "Invalid API key"}')
      end

      it "raises ExecutionError" do
        expect {
          adapter.call(prompt: "Hello", model_config: model_config)
        }.to raise_error(Brainpipe::ExecutionError, /HTTP request failed.*401/)
      end
    end
  end

  describe "#extract_text" do
    it "extracts text from response" do
      response = {
        "candidates" => [
          {
            "content" => {
              "parts" => [
                { "text" => "Hello, world!" }
              ]
            }
          }
        ]
      }

      expect(adapter.extract_text(response)).to eq("Hello, world!")
    end

    it "returns nil for empty response" do
      expect(adapter.extract_text({})).to be_nil
    end

    it "returns nil for response without candidates" do
      expect(adapter.extract_text({ "other" => "data" })).to be_nil
    end
  end

  describe "#extract_image" do
    it "extracts image from response with inlineData" do
      response = {
        "candidates" => [
          {
            "content" => {
              "parts" => [
                {
                  "inlineData" => {
                    "mimeType" => "image/png",
                    "data" => "aGVsbG8="
                  }
                }
              ]
            }
          }
        ]
      }

      image = adapter.extract_image(response)
      expect(image).to be_a(Brainpipe::Image)
      expect(image.mime_type).to eq("image/png")
      expect(image.base64).to eq("aGVsbG8=")
    end

    it "returns nil when no inlineData in response" do
      response = {
        "candidates" => [
          {
            "content" => {
              "parts" => [
                { "text" => "Hello, world!" }
              ]
            }
          }
        ]
      }

      expect(adapter.extract_image(response)).to be_nil
    end

    it "returns nil for empty response" do
      expect(adapter.extract_image({})).to be_nil
    end

    it "returns nil for nil response" do
      expect(adapter.extract_image(nil)).to be_nil
    end

    it "finds image in mixed content response" do
      response = {
        "candidates" => [
          {
            "content" => {
              "parts" => [
                { "text" => "Here's your image:" },
                {
                  "inlineData" => {
                    "mimeType" => "image/jpeg",
                    "data" => "dGVzdA=="
                  }
                }
              ]
            }
          }
        ]
      }

      image = adapter.extract_image(response)
      expect(image).to be_a(Brainpipe::Image)
      expect(image.mime_type).to eq("image/jpeg")
    end
  end
end
