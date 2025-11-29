require_relative "provider_adapters/base"
require_relative "provider_adapters/openai"
require_relative "provider_adapters/anthropic"
require_relative "provider_adapters/google_ai"

module Brainpipe
  module ProviderAdapters
    @registry = {}

    class << self
      def register(provider, adapter_class)
        @registry[normalize_provider(provider)] = adapter_class
      end

      def for(provider)
        normalized = normalize_provider(provider)
        adapter = @registry[normalized]
        raise ConfigurationError, "Unknown provider: '#{provider}'" unless adapter
        adapter.new
      end

      def normalize_provider(provider)
        provider.to_s.tr("-", "_").to_sym
      end

      def to_baml_provider(provider)
        normalize_provider(provider).to_s.tr("_", "-")
      end

      def clear!
        @registry.clear
      end

      def reset!
        @registry.clear
        register_defaults
      end

      def register_defaults
        register(:openai, OpenAI)
        register(:anthropic, Anthropic)
        register(:google_ai, GoogleAI)
      end
    end

    register_defaults
  end
end
