module Brainpipe
  module Rails
    class Engine < ::Rails::Engine
      isolate_namespace Brainpipe::Rails

      config.generators do |g|
        g.test_framework :rspec
      end

      # Set engine root for proper config file loading
      def self.root
        @root ||= Pathname.new(File.expand_path("../../..", __dir__))
      end

      routes do
        get "health", to: "pipelines#health", as: :health
        get "pipelines", to: "pipelines#index", as: :pipelines
        get "pipelines/:name", to: "pipelines#show", as: :pipeline
        post "pipelines/:name", to: "pipelines#execute", as: :execute_pipeline
        post "pipelines/:name/stream", to: "pipelines#stream", as: :stream_pipeline
        post "pipelines/:name/async", to: "pipelines#execute_async", as: :async_pipeline
        get "pipelines/:name/executions/:id", to: "pipelines#execution_status", as: :pipeline_execution
      end
    end
  end
end
