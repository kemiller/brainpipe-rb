Rails.application.config.brainpipe.tap do |config|
  # Path to pipe configuration YAML files (default: config/brainpipe)
  # config.config_path = Rails.root.join("config/brainpipe")

  # Enable debug output in all environments (default: development only)
  # config.debug = Rails.env.development?

  # Additional paths to autoload operations from
  # config.autoload_paths = [Rails.root.join("lib/operations")]

  # Which pipes to expose via API
  # :all       - All loaded pipes (default)
  # :none      - No pipes (disable API)
  # [:a, :b]   - Only specific pipes
  # config.expose_pipes = :all

  # API authentication (receives request, return truthy for authenticated)
  # config.api_authentication = ->(request) {
  #   request.headers["X-API-Key"] == Rails.application.credentials.brainpipe_api_key
  # }

  # Before/after hooks for pipeline execution
  # config.before_execute = ->(pipe_name, input, request) {
  #   Rails.logger.info "Executing #{pipe_name} with #{input.keys}"
  # }
  # config.after_execute = ->(pipe_name, result, request) {
  #   # Track metrics, audit log, etc.
  # }

  # ActiveJob queue name for async execution (default: :brainpipe)
  # config.async_queue = :brainpipe

  # Enable ActiveRecord tracking for async executions (default: true)
  # config.track_executions = true

  # How long to keep execution records (default: 7.days)
  # config.execution_retention = 7.days
end
