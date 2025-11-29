require "base64"

RSpec.describe Brainpipe::Extractors::GeminiImage do
  let(:encoded_data) { Base64.strict_encode64("fake image data") }
  let(:mime_type) { "image/png" }

  def gemini_response_with_image(data: encoded_data, mime: mime_type)
    {
      "candidates" => [
        {
          "content" => {
            "parts" => [
              {
                "inlineData" => {
                  "mimeType" => mime,
                  "data" => data
                }
              }
            ]
          }
        }
      ]
    }
  end

  describe ".call" do
    it "extracts image from valid Gemini response with inlineData" do
      response = gemini_response_with_image

      result = described_class.call(response)

      expect(result).to be_a(Brainpipe::Image)
      expect(result.base64).to eq(encoded_data)
      expect(result.mime_type).to eq(mime_type)
    end

    it "returns nil when response is nil" do
      expect(described_class.call(nil)).to be_nil
    end

    it "returns nil when response is empty" do
      expect(described_class.call({})).to be_nil
    end

    it "returns nil when candidates is missing" do
      response = { "other" => "data" }
      expect(described_class.call(response)).to be_nil
    end

    it "returns nil when candidates is not an array" do
      response = { "candidates" => "not an array" }
      expect(described_class.call(response)).to be_nil
    end

    it "returns nil when candidates is empty" do
      response = { "candidates" => [] }
      expect(described_class.call(response)).to be_nil
    end

    it "returns nil when content is missing" do
      response = { "candidates" => [{ "other" => "data" }] }
      expect(described_class.call(response)).to be_nil
    end

    it "returns nil when parts is missing" do
      response = { "candidates" => [{ "content" => {} }] }
      expect(described_class.call(response)).to be_nil
    end

    it "returns nil when parts is not an array" do
      response = { "candidates" => [{ "content" => { "parts" => "not array" } }] }
      expect(described_class.call(response)).to be_nil
    end

    it "handles response with text-only parts" do
      response = {
        "candidates" => [
          {
            "content" => {
              "parts" => [
                { "text" => "This is just text, no image" }
              ]
            }
          }
        ]
      }

      expect(described_class.call(response)).to be_nil
    end

    it "extracts image when mixed text and image parts" do
      response = {
        "candidates" => [
          {
            "content" => {
              "parts" => [
                { "text" => "Here is the image:" },
                {
                  "inlineData" => {
                    "mimeType" => mime_type,
                    "data" => encoded_data
                  }
                }
              ]
            }
          }
        ]
      }

      result = described_class.call(response)
      expect(result).to be_a(Brainpipe::Image)
      expect(result.base64).to eq(encoded_data)
    end

    it "returns first image when multiple images present" do
      first_data = Base64.strict_encode64("first image")
      second_data = Base64.strict_encode64("second image")

      response = {
        "candidates" => [
          {
            "content" => {
              "parts" => [
                { "inlineData" => { "mimeType" => "image/png", "data" => first_data } },
                { "inlineData" => { "mimeType" => "image/jpeg", "data" => second_data } }
              ]
            }
          }
        ]
      }

      result = described_class.call(response)
      expect(result.base64).to eq(first_data)
      expect(result.mime_type).to eq("image/png")
    end

    it "skips parts with missing mimeType" do
      response = {
        "candidates" => [
          {
            "content" => {
              "parts" => [
                { "inlineData" => { "data" => encoded_data } },
                { "inlineData" => { "mimeType" => mime_type, "data" => encoded_data } }
              ]
            }
          }
        ]
      }

      result = described_class.call(response)
      expect(result).to be_a(Brainpipe::Image)
    end

    it "skips parts with missing data" do
      response = {
        "candidates" => [
          {
            "content" => {
              "parts" => [
                { "inlineData" => { "mimeType" => mime_type } },
                { "inlineData" => { "mimeType" => mime_type, "data" => encoded_data } }
              ]
            }
          }
        ]
      }

      result = described_class.call(response)
      expect(result).to be_a(Brainpipe::Image)
    end

    it "handles different MIME types" do
      response = gemini_response_with_image(mime: "image/jpeg")

      result = described_class.call(response)
      expect(result.mime_type).to eq("image/jpeg")
    end
  end
end
