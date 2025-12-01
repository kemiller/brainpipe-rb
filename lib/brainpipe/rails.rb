require_relative "rails/railtie"
require_relative "rails/engine"
require_relative "rails/routes"
require_relative "rails/log_subscriber"
require_relative "rails/streaming_collector"
require_relative "rails/pipelines_controller"
require_relative "rails/pipeline_job"
require_relative "rails/execution" if defined?(ActiveRecord)
