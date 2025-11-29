RSpec.describe Brainpipe::ProviderAdapters::Anthropic do
  let(:adapter) { described_class.new }

  let(:model_config) do
    Brainpipe::ModelConfig.new(
      name: :claude,
      provider: :anthropic,
      model: "claude-sonnet-4-20250514",
      capabilities: [:text_to_text],
      options: { api_key: "test-api-key" }
    )
  end

  describe "#call" do
    let(:mock_response) do
      {
        "content" => [
          {
            "type" => "text",
            "text" => "Hello, world!"
          }
        ]
      }
    end

    before do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 200, body: JSON.generate(mock_response), headers: { "Content-Type" => "application/json" })
    end

    it "makes request to Anthropic API" do
      adapter.call(prompt: "Hello", model_config: model_config)

      expect(WebMock).to have_requested(:post, "https://api.anthropic.com/v1/messages")
        .with(headers: {
          "x-api-key" => "test-api-key",
          "anthropic-version" => "2023-06-01",
          "Content-Type" => "application/json"
        })
    end

    it "sends prompt as user message" do
      adapter.call(prompt: "Hello", model_config: model_config)

      expect(WebMock).to have_requested(:post, "https://api.anthropic.com/v1/messages")
        .with { |req|
          body = JSON.parse(req.body)
          body["messages"] == [{ "role" => "user", "content" => "Hello" }]
        }
    end

    it "sends model from config" do
      adapter.call(prompt: "Hello", model_config: model_config)

      expect(WebMock).to have_requested(:post, "https://api.anthropic.com/v1/messages")
        .with { |req|
          body = JSON.parse(req.body)
          body["model"] == "claude-sonnet-4-20250514"
        }
    end

    it "includes default max_tokens" do
      adapter.call(prompt: "Hello", model_config: model_config)

      expect(WebMock).to have_requested(:post, "https://api.anthropic.com/v1/messages")
        .with { |req|
          body = JSON.parse(req.body)
          body["max_tokens"] == 4096
        }
    end

    it "returns parsed response" do
      result = adapter.call(prompt: "Hello", model_config: model_config)
      expect(result).to eq(mock_response)
    end

    context "with images" do
      let(:image) { Brainpipe::Image.from_base64("aGVsbG8=", mime_type: "image/png") }

      it "sends images as content array with base64 data" do
        adapter.call(prompt: "What's in this image?", model_config: model_config, images: [image])

        expect(WebMock).to have_requested(:post, "https://api.anthropic.com/v1/messages")
          .with { |req|
            body = JSON.parse(req.body)
            content = body["messages"][0]["content"]
            content.is_a?(Array) &&
              content[0]["type"] == "image" &&
              content[0]["source"]["type"] == "base64" &&
              content[0]["source"]["media_type"] == "image/png" &&
              content[0]["source"]["data"] == "aGVsbG8=" &&
              content[1] == { "type" => "text", "text" => "What's in this image?" }
          }
      end
    end

    context "with model options" do
      let(:model_config_with_options) do
        Brainpipe::ModelConfig.new(
          name: :claude,
          provider: :anthropic,
          model: "claude-sonnet-4-20250514",
          capabilities: [:text_to_text],
          options: { api_key: "test-api-key", temperature: 0.7, max_tokens: 2000 }
        )
      end

      it "includes allowed options in request" do
        adapter.call(prompt: "Hello", model_config: model_config_with_options)

        expect(WebMock).to have_requested(:post, "https://api.anthropic.com/v1/messages")
          .with { |req|
            body = JSON.parse(req.body)
            body["temperature"] == 0.7 && body["max_tokens"] == 2000
          }
      end
    end

    context "without api_key" do
      let(:model_config_no_key) do
        Brainpipe::ModelConfig.new(
          name: :claude,
          provider: :anthropic,
          model: "claude-sonnet-4-20250514",
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
        stub_request(:post, "https://api.anthropic.com/v1/messages")
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
        "content" => [
          {
            "type" => "text",
            "text" => "Hello, world!"
          }
        ]
      }

      expect(adapter.extract_text(response)).to eq("Hello, world!")
    end

    it "returns nil for empty response" do
      expect(adapter.extract_text({})).to be_nil
    end

    it "returns nil for response without content" do
      expect(adapter.extract_text({ "other" => "data" })).to be_nil
    end
  end
end
