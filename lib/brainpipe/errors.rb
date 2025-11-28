module Brainpipe
  class Error < StandardError; end

  # Configuration errors
  class ConfigurationError < Error; end
  class InvalidYAMLError < ConfigurationError; end
  class MissingOperationError < ConfigurationError; end
  class MissingModelError < ConfigurationError; end
  class MissingPipeError < ConfigurationError; end
  class CapabilityMismatchError < ConfigurationError; end
  class IncompatibleStagesError < ConfigurationError; end

  # Runtime errors
  class ExecutionError < Error; end
  class TimeoutError < ExecutionError; end
  class EmptyInputError < ExecutionError; end

  # Contract errors
  class ContractViolationError < Error; end
  class PropertyNotFoundError < ContractViolationError; end
  class TypeMismatchError < ContractViolationError; end
  class UnexpectedPropertyError < ContractViolationError; end
  class UnexpectedDeletionError < ContractViolationError; end
  class OutputCountMismatchError < ContractViolationError; end
end
