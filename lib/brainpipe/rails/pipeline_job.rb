require "net/http"
require "json"
require "ostruct"

module Brainpipe
  module Rails
    class PipelineJob < ActiveJob::Base
      queue_as { ::Rails.application.config.brainpipe.async_queue || :brainpipe }

      def perform(execution_id, pipe_name, input, options = {})
        execution = find_or_create_execution(execution_id, pipe_name)
        execution.update!(status: :running, started_at: Time.current)

        pipe = Brainpipe.pipe(pipe_name.to_sym)
        result = pipe.call(input.symbolize_keys)

        execution.update!(
          status: :completed,
          completed_at: Time.current,
          result: result.to_h
        )

        notify_webhook(options[:webhook_url], execution) if options[:webhook_url]
      rescue StandardError => e
        execution&.update!(
          status: :failed,
          completed_at: Time.current,
          error: { type: e.class.name, message: e.message }
        )

        notify_webhook(options[:webhook_url], execution) if options[:webhook_url]

        raise
      end

      private

      def find_or_create_execution(id, pipe_name)
        if defined?(Brainpipe::Rails::Execution) && ::Rails.application.config.brainpipe.track_executions
          Brainpipe::Rails::Execution.find_or_create_by!(id: id) do |e|
            e.pipe_name = pipe_name
            e.status = :pending
          end
        else
          MockExecution.new(id, pipe_name)
        end
      end

      def notify_webhook(url, execution)
        return unless url.present?

        payload = {
          execution_id: execution.id,
          pipe_name: execution.pipe_name,
          status: execution.status,
          result: execution.result,
          error: execution.error,
          started_at: execution.started_at,
          completed_at: execution.completed_at
        }

        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"

        request = Net::HTTP::Post.new(uri.path.presence || "/")
        request["Content-Type"] = "application/json"
        request.body = payload.to_json

        http.request(request)
      rescue StandardError => e
        ::Rails.logger.error "Brainpipe webhook failed: #{e.message}"
      end

      class MockExecution
        attr_accessor :id, :pipe_name, :status, :result, :error, :started_at, :completed_at

        def initialize(id, pipe_name)
          @id = id
          @pipe_name = pipe_name
          @status = :pending
          @result = {}
          @error = {}
        end

        def update!(attrs)
          attrs.each { |k, v| send("#{k}=", v) }
        end

        def completed?
          status == :completed
        end

        def failed?
          status == :failed
        end
      end
    end
  end
end
