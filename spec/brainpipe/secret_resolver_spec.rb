RSpec.describe Brainpipe::SecretResolver do
  describe "#resolve" do
    context "with plain strings" do
      let(:resolver) { described_class.new }

      it "returns plain string unchanged" do
        expect(resolver.resolve("plain value")).to eq("plain value")
      end

      it "returns empty string unchanged" do
        expect(resolver.resolve("")).to eq("")
      end

      it "returns non-string values unchanged" do
        expect(resolver.resolve(42)).to eq(42)
        expect(resolver.resolve(nil)).to be_nil
        expect(resolver.resolve(true)).to be true
      end
    end

    context "with environment variables" do
      let(:resolver) { described_class.new }

      around do |example|
        original = ENV["TEST_VAR"]
        ENV["TEST_VAR"] = "test_value"
        example.run
        ENV["TEST_VAR"] = original
      end

      it "resolves single environment variable" do
        expect(resolver.resolve("${TEST_VAR}")).to eq("test_value")
      end

      it "resolves environment variable in middle of string" do
        expect(resolver.resolve("prefix_${TEST_VAR}_suffix")).to eq("prefix_test_value_suffix")
      end

      it "resolves multiple environment variables" do
        ENV["OTHER_VAR"] = "other"
        result = resolver.resolve("${TEST_VAR}-${OTHER_VAR}")
        expect(result).to eq("test_value-other")
        ENV.delete("OTHER_VAR")
      end

      it "raises ConfigurationError for missing environment variable" do
        expect {
          resolver.resolve("${MISSING_ENV_VAR}")
        }.to raise_error(Brainpipe::ConfigurationError, /Environment variable 'MISSING_ENV_VAR' not found/)
      end
    end

    context "with secret references" do
      it "raises ConfigurationError when no secret_resolver configured" do
        resolver = described_class.new

        expect {
          resolver.resolve("secret://my-api-key")
        }.to raise_error(Brainpipe::ConfigurationError, /no secret_resolver configured/)
      end

      it "calls configured secret_resolver with reference" do
        secret_resolver_proc = ->(ref) { "resolved_#{ref}" }
        resolver = described_class.new(secret_resolver: secret_resolver_proc)

        expect(resolver.resolve("secret://my-api-key")).to eq("resolved_my-api-key")
      end

      it "passes full reference path to resolver" do
        captured_ref = nil
        secret_resolver_proc = ->(ref) { captured_ref = ref; "value" }
        resolver = described_class.new(secret_resolver: secret_resolver_proc)

        resolver.resolve("secret://path/to/secret")
        expect(captured_ref).to eq("path/to/secret")
      end
    end
  end

  describe "#resolve_hash" do
    let(:resolver) { described_class.new }

    around do |example|
      original = ENV["API_KEY"]
      ENV["API_KEY"] = "secret123"
      example.run
      ENV["API_KEY"] = original
    end

    it "resolves string values in hash" do
      result = resolver.resolve_hash({
        key: "${API_KEY}",
        plain: "unchanged"
      })

      expect(result[:key]).to eq("secret123")
      expect(result[:plain]).to eq("unchanged")
    end

    it "resolves nested hashes" do
      result = resolver.resolve_hash({
        outer: {
          inner: "${API_KEY}"
        }
      })

      expect(result[:outer][:inner]).to eq("secret123")
    end

    it "resolves arrays" do
      result = resolver.resolve_hash({
        keys: ["${API_KEY}", "plain"]
      })

      expect(result[:keys]).to eq(["secret123", "plain"])
    end

    it "handles mixed nesting" do
      result = resolver.resolve_hash({
        config: {
          keys: ["${API_KEY}"],
          nested: {
            value: "${API_KEY}"
          }
        },
        plain: 42
      })

      expect(result[:config][:keys]).to eq(["secret123"])
      expect(result[:config][:nested][:value]).to eq("secret123")
      expect(result[:plain]).to eq(42)
    end

    it "preserves non-string values" do
      result = resolver.resolve_hash({
        number: 42,
        bool: true,
        nil_val: nil
      })

      expect(result[:number]).to eq(42)
      expect(result[:bool]).to be true
      expect(result[:nil_val]).to be_nil
    end
  end
end
