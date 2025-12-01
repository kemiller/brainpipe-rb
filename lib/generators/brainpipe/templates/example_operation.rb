class ExampleOperation < Brainpipe::Operation
  reads :input, String
  sets :output, String

  def call(namespace)
    input_value = namespace[:input]
    namespace[:output] = "Processed: #{input_value}"
    namespace
  end
end
