require "rails/generators"
require "rails/generators/active_record"

module Brainpipe
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      include ::Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :async, type: :boolean, default: false,
        desc: "Generate migration for async execution tracking"

      def self.next_migration_number(dirname)
        ::ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def create_initializer
        template "brainpipe.rb", "config/initializers/brainpipe.rb"
      end

      def create_config_directory
        empty_directory "config/brainpipe"
        template "models.yml", "config/brainpipe/models.yml"
      end

      def create_operations_directory
        empty_directory "app/operations"
        template "example_operation.rb", "app/operations/example_operation.rb"
      end

      def create_pipelines_directory
        empty_directory "app/pipelines"
      end

      def add_routes
        route 'mount Brainpipe::Rails::Engine => "/brainpipe"'
      end

      def create_migration
        return unless options[:async]

        migration_template "create_brainpipe_executions.rb",
          "db/migrate/create_brainpipe_executions.rb"
      end
    end
  end
end
