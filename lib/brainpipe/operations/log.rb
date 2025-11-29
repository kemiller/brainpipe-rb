module Brainpipe
  module Operations
    class Log < Operation
      LEVELS = [:debug, :info, :warn, :error].freeze

      def initialize(model: nil, options: {})
        @fields = options[:fields] ? Array(options[:fields]).map(&:to_sym) : nil
        @message = options[:message]
        @level = options.fetch(:level, :info).to_sym
        @logger = options[:logger]

        unless LEVELS.include?(@level)
          raise ConfigurationError, "Log level must be one of: #{LEVELS.join(', ')}"
        end

        super
      end

      def declared_reads(prefix_schema = {})
        {}
      end

      def declared_sets(prefix_schema = {})
        {}
      end

      def declared_deletes(prefix_schema = {})
        []
      end

      def create
        fields = @fields
        message = @message
        level = @level
        logger = @logger

        ->(namespaces) do
          namespaces.each do |ns|
            log_output = build_log_output(ns, fields, message)
            write_log(logger, level, log_output)
          end
          namespaces
        end
      end

      private

      def build_log_output(ns, fields, message)
        parts = []
        parts << message if message

        if fields
          field_values = fields.map { |f| "#{f}=#{ns[f].inspect}" }
          parts << field_values.join(", ")
        else
          parts << ns.to_h.inspect
        end

        parts.join(": ")
      end

      def write_log(logger, level, output)
        if logger
          logger.send(level, output)
        else
          prefix = "[Brainpipe::Log][#{level.upcase}]"
          $stderr.puts "#{prefix} #{output}"
        end
      end
    end
  end
end
