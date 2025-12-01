require "securerandom"

module Brainpipe
  module Rails
    class PipelinesController < ActionController::API
      include ActionController::Live

      before_action :authenticate!, if: -> { authentication_configured? }
      before_action :set_pipe, only: [:show, :execute, :stream, :execute_async]
      before_action :check_pipe_exposed, only: [:show, :execute, :stream, :execute_async]

      def health
        render json: {
          status: "ok",
          loaded: Brainpipe.loaded?,
          version: Brainpipe::VERSION
        }
      end

      def index
        pipes = exposed_pipe_names.map do |name|
          pipe = Brainpipe.pipe(name)
          {
            name: name,
            input_schema: pipe.inputs,
            output_schema: pipe.outputs
          }
        end
        render json: { pipelines: pipes }
      end

      def show
        render json: {
          name: @pipe_name,
          input_schema: @pipe.inputs,
          output_schema: @pipe.outputs,
          stages: @pipe.stages.map(&:name)
        }
      end

      def execute
        input = parse_input

        run_before_hook(input)

        result = @pipe.call(input)

        run_after_hook(result)

        render json: {
          success: true,
          result: result.to_h
        }
      rescue Brainpipe::ContractViolationError => e
        render json: { success: false, error: e.message, type: "contract_violation" }, status: 422
      rescue Brainpipe::ExecutionError => e
        render json: { success: false, error: e.message, type: "execution_error" }, status: 500
      rescue Brainpipe::TimeoutError => e
        render json: { success: false, error: e.message, type: "timeout" }, status: 504
      end

      def stream
        input = parse_input

        response.headers["Content-Type"] = "text/event-stream"
        response.headers["Cache-Control"] = "no-cache"
        response.headers["X-Accel-Buffering"] = "no"

        run_before_hook(input)

        streaming_collector = StreamingCollector.new(response.stream)

        result = @pipe.call(input, metrics_collector: streaming_collector)

        streaming_collector.send_complete(result.to_h)

        run_after_hook(result)
      rescue Brainpipe::ContractViolationError => e
        streaming_collector&.send_error("contract_violation", e.message)
      rescue Brainpipe::ExecutionError => e
        streaming_collector&.send_error("execution_error", e.message)
      rescue Brainpipe::TimeoutError => e
        streaming_collector&.send_error("timeout", e.message)
      ensure
        response.stream.close
      end

      def execute_async
        input = parse_input
        execution_id = SecureRandom.uuid

        run_before_hook(input)

        options = {
          webhook_url: params[:webhook_url]
        }

        if defined?(Execution) && rails_config.track_executions
          Execution.create!(
            id: execution_id,
            pipe_name: @pipe_name.to_s,
            status: :pending,
            input: input
          )
        end

        PipelineJob.perform_later(execution_id, @pipe_name.to_s, input, options)

        render json: {
          execution_id: execution_id,
          status: "pending",
          status_url: pipeline_execution_url(@pipe_name, execution_id)
        }, status: 202
      end

      def execution_status
        execution_id = params[:id]

        if defined?(Execution) && rails_config.track_executions
          execution = Execution.find(execution_id)
          render json: {
            execution_id: execution.id,
            pipe_name: execution.pipe_name,
            status: execution.status,
            result: execution.completed? ? execution.result : nil,
            error: execution.failed? ? execution.error : nil,
            started_at: execution.started_at,
            completed_at: execution.completed_at
          }
        else
          render json: { error: "Execution tracking not configured" }, status: 501
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Execution not found" }, status: 404
      end

      private

      def set_pipe
        @pipe_name = params[:name].to_sym
        @pipe = Brainpipe.pipe(@pipe_name)
      rescue Brainpipe::MissingPipeError
        render json: { error: "Pipeline not found: #{params[:name]}" }, status: 404
      end

      def check_pipe_exposed
        unless pipe_exposed?(@pipe_name)
          render json: { error: "Pipeline not accessible" }, status: 403
        end
      end

      def parse_input
        case request.content_type
        when /json/
          params.permit!.to_h.except(:name, :controller, :action, :webhook_url).symbolize_keys
        when /form/
          params.permit!.to_h.except(:name, :controller, :action, :webhook_url).symbolize_keys
        else
          body = request.body.read
          body.empty? ? {} : JSON.parse(body, symbolize_names: true)
        end
      end

      def exposed_pipe_names
        case rails_config.expose_pipes
        when :all
          Brainpipe.pipe_names
        when :none
          []
        when Array
          rails_config.expose_pipes.map(&:to_sym)
        else
          []
        end
      end

      def pipe_exposed?(name)
        case rails_config.expose_pipes
        when :all then true
        when :none then false
        when Array then rails_config.expose_pipes.map(&:to_sym).include?(name.to_sym)
        else false
        end
      end

      def authentication_configured?
        rails_config.api_authentication.present?
      end

      def authenticate!
        unless rails_config.api_authentication.call(request)
          render json: { error: "Unauthorized" }, status: 401
        end
      end

      def run_before_hook(input)
        rails_config.before_execute&.call(@pipe_name, input, request)
      end

      def run_after_hook(result)
        rails_config.after_execute&.call(@pipe_name, result, request)
      end

      def rails_config
        ::Rails.application.config.brainpipe
      end
    end
  end
end
