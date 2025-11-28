RSpec.describe "Brainpipe error hierarchy" do
  describe Brainpipe::Error do
    it "inherits from StandardError" do
      expect(Brainpipe::Error.superclass).to eq(StandardError)
    end

    it "can be raised with message" do
      expect { raise Brainpipe::Error, "test message" }
        .to raise_error(Brainpipe::Error, "test message")
    end
  end

  describe "configuration errors" do
    it "ConfigurationError inherits from Error" do
      expect(Brainpipe::ConfigurationError.superclass).to eq(Brainpipe::Error)
    end

    it "InvalidYAMLError inherits from ConfigurationError" do
      expect(Brainpipe::InvalidYAMLError.superclass).to eq(Brainpipe::ConfigurationError)
    end

    it "MissingOperationError inherits from ConfigurationError" do
      expect(Brainpipe::MissingOperationError.superclass).to eq(Brainpipe::ConfigurationError)
    end

    it "MissingModelError inherits from ConfigurationError" do
      expect(Brainpipe::MissingModelError.superclass).to eq(Brainpipe::ConfigurationError)
    end

    it "MissingPipeError inherits from ConfigurationError" do
      expect(Brainpipe::MissingPipeError.superclass).to eq(Brainpipe::ConfigurationError)
    end

    it "CapabilityMismatchError inherits from ConfigurationError" do
      expect(Brainpipe::CapabilityMismatchError.superclass).to eq(Brainpipe::ConfigurationError)
    end

    it "IncompatibleStagesError inherits from ConfigurationError" do
      expect(Brainpipe::IncompatibleStagesError.superclass).to eq(Brainpipe::ConfigurationError)
    end

    it "configuration errors can be rescued as Error" do
      expect {
        begin
          raise Brainpipe::MissingModelError, "model not found"
        rescue Brainpipe::Error
        end
      }.not_to raise_error
    end
  end

  describe "runtime errors" do
    it "ExecutionError inherits from Error" do
      expect(Brainpipe::ExecutionError.superclass).to eq(Brainpipe::Error)
    end

    it "TimeoutError inherits from ExecutionError" do
      expect(Brainpipe::TimeoutError.superclass).to eq(Brainpipe::ExecutionError)
    end

    it "EmptyInputError inherits from ExecutionError" do
      expect(Brainpipe::EmptyInputError.superclass).to eq(Brainpipe::ExecutionError)
    end

    it "runtime errors can be rescued as Error" do
      expect {
        begin
          raise Brainpipe::TimeoutError, "operation timed out"
        rescue Brainpipe::Error
        end
      }.not_to raise_error
    end
  end

  describe "contract errors" do
    it "ContractViolationError inherits from Error" do
      expect(Brainpipe::ContractViolationError.superclass).to eq(Brainpipe::Error)
    end

    it "PropertyNotFoundError inherits from ContractViolationError" do
      expect(Brainpipe::PropertyNotFoundError.superclass).to eq(Brainpipe::ContractViolationError)
    end

    it "TypeMismatchError inherits from ContractViolationError" do
      expect(Brainpipe::TypeMismatchError.superclass).to eq(Brainpipe::ContractViolationError)
    end

    it "UnexpectedPropertyError inherits from ContractViolationError" do
      expect(Brainpipe::UnexpectedPropertyError.superclass).to eq(Brainpipe::ContractViolationError)
    end

    it "UnexpectedDeletionError inherits from ContractViolationError" do
      expect(Brainpipe::UnexpectedDeletionError.superclass).to eq(Brainpipe::ContractViolationError)
    end

    it "OutputCountMismatchError inherits from ContractViolationError" do
      expect(Brainpipe::OutputCountMismatchError.superclass).to eq(Brainpipe::ContractViolationError)
    end

    it "contract errors can be rescued as Error" do
      expect {
        begin
          raise Brainpipe::TypeMismatchError, "expected String, got Integer"
        rescue Brainpipe::Error
        end
      }.not_to raise_error
    end
  end
end
