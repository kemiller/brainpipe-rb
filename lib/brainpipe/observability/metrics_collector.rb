module Brainpipe
  module Observability
    class MetricsCollector
      def operation_started(operation_class:, namespace:, stage: nil, pipe: nil)
      end

      def operation_completed(operation_class:, namespace:, duration_ms:, stage: nil, pipe: nil)
      end

      def operation_failed(operation_class:, namespace:, error:, duration_ms:, stage: nil, pipe: nil)
      end

      def model_called(model_config:, input:, output:, tokens_in:, tokens_out:, duration_ms:)
      end

      def stage_started(stage:, namespace_count:, pipe: nil)
      end

      def stage_completed(stage:, namespace_count:, duration_ms:, pipe: nil)
      end

      def stage_failed(stage:, error:, duration_ms:, pipe: nil)
      end

      def pipe_started(pipe:, input:)
      end

      def pipe_completed(pipe:, input:, output:, duration_ms:, operations_count:)
      end

      def pipe_failed(pipe:, error:, duration_ms:)
      end
    end
  end
end
