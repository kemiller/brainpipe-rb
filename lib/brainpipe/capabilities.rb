module Brainpipe
  module Capabilities
    TEXT_TO_TEXT = :text_to_text
    TEXT_TO_IMAGE = :text_to_image
    IMAGE_TO_TEXT = :image_to_text
    TEXT_IMAGE_TO_TEXT = :text_image_to_text
    TEXT_TO_AUDIO = :text_to_audio
    AUDIO_TO_TEXT = :audio_to_text
    TEXT_TO_EMBEDDING = :text_to_embedding
    IMAGE_EDIT = :image_edit

    VALID_CAPABILITIES = [
      TEXT_TO_TEXT,
      TEXT_TO_IMAGE,
      IMAGE_TO_TEXT,
      TEXT_IMAGE_TO_TEXT,
      TEXT_TO_AUDIO,
      AUDIO_TO_TEXT,
      TEXT_TO_EMBEDDING,
      IMAGE_EDIT
    ].freeze

    def self.valid?(capability)
      VALID_CAPABILITIES.include?(capability.to_sym)
    end
  end
end
