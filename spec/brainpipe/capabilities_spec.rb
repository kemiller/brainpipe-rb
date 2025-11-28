RSpec.describe Brainpipe::Capabilities do
  describe "constants" do
    it "defines TEXT_TO_TEXT" do
      expect(described_class::TEXT_TO_TEXT).to eq(:text_to_text)
    end

    it "defines TEXT_TO_IMAGE" do
      expect(described_class::TEXT_TO_IMAGE).to eq(:text_to_image)
    end

    it "defines IMAGE_TO_TEXT" do
      expect(described_class::IMAGE_TO_TEXT).to eq(:image_to_text)
    end

    it "defines TEXT_IMAGE_TO_TEXT" do
      expect(described_class::TEXT_IMAGE_TO_TEXT).to eq(:text_image_to_text)
    end

    it "defines TEXT_TO_AUDIO" do
      expect(described_class::TEXT_TO_AUDIO).to eq(:text_to_audio)
    end

    it "defines AUDIO_TO_TEXT" do
      expect(described_class::AUDIO_TO_TEXT).to eq(:audio_to_text)
    end

    it "defines TEXT_TO_EMBEDDING" do
      expect(described_class::TEXT_TO_EMBEDDING).to eq(:text_to_embedding)
    end
  end

  describe "VALID_CAPABILITIES" do
    it "includes all capability constants" do
      expect(described_class::VALID_CAPABILITIES).to include(
        :text_to_text,
        :text_to_image,
        :image_to_text,
        :text_image_to_text,
        :text_to_audio,
        :audio_to_text,
        :text_to_embedding
      )
    end

    it "is frozen" do
      expect(described_class::VALID_CAPABILITIES).to be_frozen
    end
  end

  describe ".valid?" do
    it "returns true for valid symbol capability" do
      expect(described_class.valid?(:text_to_text)).to be true
    end

    it "returns true for valid string capability" do
      expect(described_class.valid?("text_to_text")).to be true
    end

    it "returns false for invalid capability" do
      expect(described_class.valid?(:not_a_capability)).to be false
    end

    it "returns false for empty string" do
      expect(described_class.valid?("")).to be false
    end
  end
end
