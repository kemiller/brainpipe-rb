I'm designing a ruby library that will make it easier to chain together
AI Api calls and related tasks.  It's called brainpipe, and you can
think of it as Rack for AI. The basic model is this:

* A pipe is a sequence of operations
* Operations are discrete tasks, such as a call to a BAML function for LLM or GenAI operations
* There's a shared namespace of properties that can be read, set, or deleted by operations, along with their expected types (if setting/reading)
* Operations are classes/structures that can define their operations, but also declare which properties they read, set, and delete.
* Operations are organized into stages; stages can have one or more operations, with the following semantics:
  - An array of one or more property sets is passed to a stage
  - A stage can be configured to do one of a few things with the array
    + Merge all the arrays, last in wins, and send each to each operation in the stage
    + Send each set in the array to a distinct instance of each operation
    + Send the whole array to each operation
* The end goal is to enable calling an API with the pipe and have it process and return the output. 
