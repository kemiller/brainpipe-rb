module Brainpipe
  module Observability
    class Debug
      attr_reader :output

      def initialize(output: $stdout)
        @output = output
        @indent_level = 0
      end

      def pipe_start(pipe_name, input)
        log "▶ Pipe '#{pipe_name}' started"
        indent do
          log "Input: #{truncate(input.to_h.inspect)}"
        end
      end

      def pipe_end(pipe_name, output, duration_ms)
        log "✓ Pipe '#{pipe_name}' completed in #{format_duration(duration_ms)}"
        indent do
          log "Output: #{truncate(output.to_h.inspect)}"
        end
      end

      def pipe_error(pipe_name, error, duration_ms)
        log "✗ Pipe '#{pipe_name}' failed after #{format_duration(duration_ms)}"
        indent do
          log "Error: #{error.class}: #{error.message}"
        end
      end

      def stage_start(stage_name, mode, namespace_count)
        log "├─ Stage '#{stage_name}' (#{mode}) started with #{namespace_count} namespace(s)"
      end

      def stage_end(stage_name, duration_ms)
        log "├─ Stage '#{stage_name}' completed in #{format_duration(duration_ms)}"
      end

      def stage_error(stage_name, error, duration_ms)
        log "├─ Stage '#{stage_name}' failed after #{format_duration(duration_ms)}: #{error.class}"
      end

      def operation_start(operation_class, namespace_keys)
        log "│  ├─ #{operation_class} started"
        indent do
          log "│  │  Input keys: #{namespace_keys.join(', ')}"
        end
      end

      def operation_end(operation_class, duration_ms, output_keys)
        log "│  ├─ #{operation_class} completed in #{format_duration(duration_ms)}"
        indent do
          log "│  │  Output keys: #{output_keys.join(', ')}"
        end
      end

      def operation_error(operation_class, error, duration_ms)
        log "│  ├─ #{operation_class} failed after #{format_duration(duration_ms)}"
        indent do
          log "│  │  Error: #{error.class}: #{truncate(error.message, 100)}"
        end
      end

      def namespace_state(label, namespace)
        log "│  │  #{label}: #{truncate(namespace.to_h.inspect)}"
      end

      private

      def log(message)
        output.puts("  " * @indent_level + "[Brainpipe] #{message}")
      end

      def indent
        @indent_level += 1
        yield
      ensure
        @indent_level -= 1
      end

      def format_duration(ms)
        if ms < 1000
          "#{ms.round(2)}ms"
        else
          "#{(ms / 1000.0).round(2)}s"
        end
      end

      def truncate(str, max_length = 200)
        return str if str.length <= max_length
        "#{str[0, max_length]}..."
      end
    end
  end
end
