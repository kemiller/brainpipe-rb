module Brainpipe
  class SecretResolver
    ENV_VAR_PATTERN = /\$\{([^}]+)\}/
    SECRET_PREFIX = "secret://"

    def initialize(secret_resolver: nil)
      @secret_resolver = secret_resolver
    end

    def resolve(value)
      return value unless value.is_a?(String)

      if value.start_with?(SECRET_PREFIX)
        resolve_secret(value)
      elsif value.match?(ENV_VAR_PATTERN)
        resolve_env_vars(value)
      else
        value
      end
    end

    def resolve_hash(hash)
      hash.transform_values { |v| resolve_value(v) }
    end

    private

    def resolve_value(value)
      case value
      when String
        resolve(value)
      when Hash
        resolve_hash(value)
      when Array
        value.map { |v| resolve_value(v) }
      else
        value
      end
    end

    def resolve_secret(value)
      ref = value.delete_prefix(SECRET_PREFIX)
      unless @secret_resolver
        raise ConfigurationError,
          "Secret reference '#{value}' found but no secret_resolver configured"
      end
      @secret_resolver.call(ref)
    end

    def resolve_env_vars(value)
      value.gsub(ENV_VAR_PATTERN) do
        env_var = $1
        ENV.fetch(env_var) do
          raise ConfigurationError,
            "Environment variable '#{env_var}' not found"
        end
      end
    end
  end
end
