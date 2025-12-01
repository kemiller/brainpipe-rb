module Brainpipe
  module Rails
    class StreamingCollector < Brainpipe::Observability::MetricsCollector
      def initialize(stream)
        @stream = stream
      end

      def pipe_started(pipe:, input:)
        send_event("pipe_started", { pipe: pipe, input_keys: input.to_h.keys })
      end

      def pipe_completed(pipe:, input:, output:, duration_ms:, operations_count:)
        send_event("pipe_completed", {
          pipe: pipe,
          duration_ms: duration_ms,
          operations_count: operations_count
        })
      end

      def pipe_failed(pipe:, error:, duration_ms:)
        send_event("pipe_failed", { pipe: pipe, error: error.message, duration_ms: duration_ms })
      end

      def stage_started(stage:, namespace_count:, pipe: nil)
        send_event("stage_started", { stage: stage, namespace_count: namespace_count })
      end

      def stage_completed(stage:, namespace_count:, duration_ms:, pipe: nil)
        send_event("stage_completed", {
          stage: stage,
          duration_ms: duration_ms,
          namespace_count: namespace_count
        })
      end

      def stage_failed(stage:, error:, duration_ms:, pipe: nil)
        send_event("stage_failed", { stage: stage, error: error.message })
      end

      def operation_started(operation_class:, namespace:, stage: nil, pipe: nil)
        send_event("operation_started", { operation: operation_class.name })
      end

      def operation_completed(operation_class:, namespace:, duration_ms:, stage: nil, pipe: nil)
        send_event("operation_completed", {
          operation: operation_class.name,
          duration_ms: duration_ms
        })
      end

      def operation_failed(operation_class:, namespace:, error:, duration_ms:, stage: nil, pipe: nil)
        send_event("operation_failed", {
          operation: operation_class.name,
          error: error.message
        })
      end

      def send_complete(result)
        send_event("complete", { result: result })
      end

      def send_error(type, message)
        send_event("error", { type: type, message: message })
      end

      private

      def send_event(event, data)
        @stream.write("event: #{event}\n")
        @stream.write("data: #{data.to_json}\n\n")
      rescue IOError
        # Client disconnected
      end
    end
  end
end
