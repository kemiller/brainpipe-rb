module Brainpipe
  module Rails
    class Railtie < ::Rails::Railtie
      config.brainpipe = ActiveSupport::OrderedOptions.new

      config.brainpipe.config_path = nil
      config.brainpipe.autoload_paths = []
      config.brainpipe.debug = false
      config.brainpipe.catch_all_routes = false
      config.brainpipe.api_authentication = nil
      config.brainpipe.before_execute = nil
      config.brainpipe.after_execute = nil
      config.brainpipe.expose_pipes = :all
      config.brainpipe.async_queue = :brainpipe
      config.brainpipe.execution_retention = 7.days
      config.brainpipe.track_executions = true

      initializer "brainpipe.autoload_paths", before: :set_autoload_paths do |app|
        ops_path = ::Rails.root.join("app/operations")
        pipes_path = ::Rails.root.join("app/pipelines")

        app.config.autoload_paths << ops_path.to_s if ops_path.exist?
        app.config.autoload_paths << pipes_path.to_s if pipes_path.exist?

        app.config.brainpipe.autoload_paths.each do |path|
          expanded = File.expand_path(path)
          app.config.autoload_paths << expanded if File.directory?(expanded)
        end
      end

      initializer "brainpipe.configure" do |app|
        Brainpipe.configure do |config|
          rails_config = app.config.brainpipe

          config.config_path = rails_config.config_path ||
                               ::Rails.root.join("config/brainpipe")

          config.debug = rails_config.debug || ::Rails.env.development?

          # Skip Brainpipe's Zeitwerk - Rails handles autoloading
          config.skip_zeitwerk = true
        end
      end

      initializer "brainpipe.load", after: "brainpipe.configure" do
        if ::Rails.env.development?
          ActiveSupport::Reloader.to_prepare { Brainpipe.load! }
        else
          Brainpipe.load!
        end
      end

      initializer "brainpipe.log_subscriber" do
        require_relative "log_subscriber"
        Brainpipe::Rails::LogSubscriber.attach_to :brainpipe
      end
    end
  end
end
