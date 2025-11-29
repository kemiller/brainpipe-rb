RSpec.describe Brainpipe::ProviderAdapters::OpenAI do
  let(:adapter) { described_class.new }

  let(:model_config) do
    Brainpipe::ModelConfig.new(
      name: :gpt4,
      provider: :openai,
      model: "gpt-4o",
      capabilities: [:text_to_text],
      options: { api_key: "test-api-key" }
    )
  end

  describe "#call" do
    let(:mock_response) do
      {
        "choices" => [
          {
            "message" => {
              "content" => "Hello, world!"
            }
          }
        ]
      }
    end

    before do
      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(status: 200, body: JSON.generate(mock_response), headers: { "Content-Type" => "application/json" })
    end

    it "makes request to OpenAI API" do
      adapter.call(prompt: "Hello", model_config: model_config)

      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/chat/completions")
        .with(headers: {
          "Authorization" => "Bearer test-api-key",
          "Content-Type" => "application/json"
        })
    end

    it "sends prompt as user message" do
      adapter.call(prompt: "Hello", model_config: model_config)

      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/chat/completions")
        .with { |req|
          body = JSON.parse(req.body)
          body["messages"] == [{ "role" => "user", "content" => "Hello" }]
        }
    end

    it "sends model from config" do
      adapter.call(prompt: "Hello", model_config: model_config)

      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/chat/completions")
        .with { |req|
          body = JSON.parse(req.body)
          body["model"] == "gpt-4o"
        }
    end

    it "sets response_format when json_mode is true" do
      adapter.call(prompt: "Hello", model_config: model_config, json_mode: true)

      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/chat/completions")
        .with { |req|
          body = JSON.parse(req.body)
          body["response_format"] == { "type" => "json_object" }
        }
    end

    it "does not set response_format when json_mode is false" do
      adapter.call(prompt: "Hello", model_config: model_config, json_mode: false)

      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/chat/completions")
        .with { |req|
          body = JSON.parse(req.body)
          !body.key?("response_format")
        }
    end

    it "returns parsed response" do
      result = adapter.call(prompt: "Hello", model_config: model_config)
      expect(result).to eq(mock_response)
    end

    context "with images" do
      let(:image) { Brainpipe::Image.from_base64("aGVsbG8=", mime_type: "image/png") }

      it "sends images as content array with data URLs" do
        adapter.call(prompt: "What's in this image?", model_config: model_config, images: [image])

        expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/chat/completions")
          .with { |req|
            body = JSON.parse(req.body)
            content = body["messages"][0]["content"]
            content.is_a?(Array) &&
              content[0] == { "type" => "text", "text" => "What's in this image?" } &&
              content[1]["type"] == "image_url" &&
              content[1]["image_url"]["url"] == "data:image/png;base64,aGVsbG8="
          }
      end
    end

    context "with model options" do
      let(:model_config_with_options) do
        Brainpipe::ModelConfig.new(
          name: :gpt4,
          provider: :openai,
          model: "gpt-4o",
          capabilities: [:text_to_text],
          options: { api_key: "test-api-key", temperature: 0.7, max_tokens: 1000 }
        )
      end

      it "includes allowed options in request" do
        adapter.call(prompt: "Hello", model_config: model_config_with_options)

        expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/chat/completions")
          .with { |req|
            body = JSON.parse(req.body)
            body["temperature"] == 0.7 && body["max_tokens"] == 1000
          }
      end
    end

    context "without api_key" do
      let(:model_config_no_key) do
        Brainpipe::ModelConfig.new(
          name: :gpt4,
          provider: :openai,
          model: "gpt-4o",
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
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
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
        "choices" => [
          {
            "message" => {
              "content" => "Hello, world!"
            }
          }
        ]
      }

      expect(adapter.extract_text(response)).to eq("Hello, world!")
    end

    it "returns nil for empty response" do
      expect(adapter.extract_text({})).to be_nil
    end

    it "returns nil for response without choices" do
      expect(adapter.extract_text({ "other" => "data" })).to be_nil
    end
  end
end
