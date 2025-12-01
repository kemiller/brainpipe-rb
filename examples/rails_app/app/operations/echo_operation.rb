class EchoOperation < Brainpipe::Operation
  reads :message, String
  sets :echo, String

  def call(namespace)
    namespace[:echo] = "Echo: #{namespace[:message]}"
    namespace
  end
end
