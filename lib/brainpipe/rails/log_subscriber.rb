module Brainpipe
  module Rails
    class LogSubscriber < ActiveSupport::LogSubscriber
      def pipe_started(event)
        info "  Brainpipe: #{event.payload[:pipe]} started"
      end

      def pipe_completed(event)
        info "  Brainpipe: #{event.payload[:pipe]} completed in #{event.duration.round(1)}ms"
      end

      def pipe_failed(event)
        error "  Brainpipe: #{event.payload[:pipe]} failed - #{event.payload[:error]}"
      end

      def operation_completed(event)
        debug "    -> #{event.payload[:operation]} (#{event.duration.round(1)}ms)"
      end
    end
  end
end
