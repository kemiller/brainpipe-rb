require_relative "boot"

require "rails"
require "action_controller/railtie"
require "active_job/railtie"

Bundler.require(*Rails.groups)

module ExampleApp
  class Application < Rails::Application
    config.load_defaults 7.1
    config.eager_load = false
    config.secret_key_base = "test_secret_key_base_for_example_app"
    config.hosts.clear
  end
end
