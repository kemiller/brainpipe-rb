# Brainpipe

A Ruby gem for building type-safe, observable LLM pipelines with contract validation.

Brainpipe provides a declarative DSL for composing operations into pipelines, with built-in support for parallel execution, type checking, and BAML integration.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'brainpipe'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install brainpipe

## Quick Start

The preferred way to define pipelines is through YAML configuration files.

### Directory Structure

```
config/brainpipe/
├── config.yml          # Model definitions
└── pipes/
    └── my_pipeline.yml # Pipeline definitions (one per file)
```

### 1. Define Models

```yaml
# config.yaml
models:
  openai:
    provider: openai
    model: gpt-4o-mini
    capabilities:
      - text_to_text
    options:
      api_key: ${OPENAI_API_KEY}

  anthropic:
    provider: anthropic
    model: claude-3-haiku-20240307
    capabilities:
      - text_to_text
    options:
      api_key: ${ANTHROPIC_API_KEY}
```

### 2. Define a Pipeline

```yaml
# pipes/entity_extractor.yml
name: entity_extractor

stages:
  - name: extract
    mode: merge
    operations:
      - type: LlmCall
        model: openai
        options:
          capability: text_to_text
          prompt_file: ../prompts/extract_entities.mustache
          inputs:
            input_text: String
            entity_types: Array
          outputs:
            entities: Array
            summary: String
```

### 3. Load and Run

```ruby
require 'brainpipe'

Brainpipe.configure do |config|
  config.config_path = "config/brainpipe"
end

Brainpipe.load!

pipe = Brainpipe.pipe(:entity_extractor)
result = pipe.call(
  input_text: "John Smith works at Acme Corp in New York.",
  entity_types: ["PERSON", "ORGANIZATION", "LOCATION"]
)

puts result[:entities]
puts result[:summary]
```

## Configuration Files

### Model Configuration

The `config.yml` file defines all available models:

```yaml
debug: true  # Optional: enable debug output

models:
  model_name:
    provider: openai|anthropic|google-ai
    model: "model-identifier"
    capabilities:
      - text_to_text
      - image_to_text
      - image_edit
      - text_to_image
    options:
      api_key: ${ENV_VAR_NAME}
      # Provider-specific options
```

Environment variables use `${VAR_NAME}` syntax and are resolved at load time.

### Pipeline Configuration

Each file in `pipes/` defines one pipeline:

```yaml
name: pipeline_name
timeout: 30  # Optional: global timeout in seconds

stages:
  - name: stage_name
    mode: merge|fan_out|batch
    merge_strategy: last_in|first_in|collate|disjoint  # Optional
    timeout: 10  # Optional: stage-specific timeout
    operations:
      - type: OperationClassName
        model: model_name  # Optional: which model to use
        options:
          # Operation-specific configuration
```

### Built-in Operations for Config Files

| Operation | Purpose |
|-----------|---------|
| `LlmCall` | Generic LLM call with prompt templates |
| `Baml` | BAML function calls with structured I/O |
| `Explode` | Split arrays into multiple namespaces |
| `Collapse` | Merge namespaces back into arrays |
| `Link` | Copy, move, set, or delete properties |
| `Filter` | Keep/drop namespaces based on conditions |
| `Merge` | Combine multiple properties into one |
| `Log` | Debug logging |

### Data Transformation Example

A pipeline using only data operations (no LLM):

```yaml
name: data_transformer

stages:
  - name: explode_items
    mode: batch
    operations:
      - type: Explode
        options:
          split:
            order_ids: order_id
            products: product
            quantities: quantity

  - name: enrich_items
    mode: batch
    operations:
      - type: Link
        options:
          copy:
            product: product_name
          set:
            currency: "USD"

  - name: collapse_items
    mode: batch
    operations:
      - type: Collapse
        options:
          merge:
            order_id: collect
            product: collect
            quantity: sum
            currency: equal
```

## Programmatic Definition

For dynamic pipelines or custom operations, use the programmatic API:

```ruby
require 'brainpipe'

# Configure Brainpipe with a model
Brainpipe.configure do |config|
  config.model :gpt4 do
    provider :openai
    model "gpt-4"
    capabilities :text_to_text
    api_key "${OPENAI_API_KEY}"
  end
end

# Define a custom operation
class SummarizeText < Brainpipe::Operation
  reads :text, String
  sets :summary, String
  requires_model :text_to_text

  execute do |ns|
    { summary: "Summary of: #{ns[:text]}" }
  end
end

# Build and run a pipeline
pipe = Brainpipe::Pipe.new(
  name: :summarize,
  stages: [
    Brainpipe::Stage.new(
      name: :process,
      mode: :merge,
      operations: [SummarizeText.new]
    )
  ]
)

result = pipe.call(text: "Long document content...")
puts result[:summary]
```

## Core Concepts

### Namespaces

A `Namespace` is an immutable property bag that flows through the pipeline:

```ruby
ns = Brainpipe::Namespace.new(name: "Alice", age: 30)
ns[:name]                    # => "Alice"
ns.merge(city: "NYC")        # => new Namespace with name, age, city
ns.delete(:age)              # => new Namespace with only name
ns.to_h                      # => { name: "Alice", age: 30 }
```

### Operations

Operations are the building blocks of pipelines. Define what properties they read, set, and delete:

```ruby
class MyOperation < Brainpipe::Operation
  reads :input, String                    # Required input
  reads :optional_input, optional: true   # Optional input
  sets :output, String                    # Will set this property
  deletes :input                          # Will remove this property

  execute do |ns|
    { output: ns[:input].upcase }
  end
end
```

For more control, override the `call` method:

```ruby
class BatchOperation < Brainpipe::Operation
  reads :items, [String]
  sets :processed, [String]

  def call(namespaces)
    namespaces.map do |ns|
      ns.merge(processed: ns[:items].map(&:upcase))
    end
  end
end
```

### Stages

Stages group operations and define execution modes:

```ruby
# Merge mode: combine all namespaces, run operations, return single result
stage = Brainpipe::Stage.new(
  name: :combine,
  mode: :merge,
  operations: [Op1.new, Op2.new]
)

# Fan-out mode: run operations on each namespace in parallel
stage = Brainpipe::Stage.new(
  name: :parallel,
  mode: :fan_out,
  operations: [ProcessItem.new]
)

# Batch mode: pass entire namespace array to operations
stage = Brainpipe::Stage.new(
  name: :batch,
  mode: :batch,
  operations: [BatchOp.new]
)
```

**Merge Strategies** (for parallel operations in a stage):

```ruby
stage = Brainpipe::Stage.new(
  name: :parallel_ops,
  mode: :merge,
  merge_strategy: :last_in,   # Last to complete wins (default)
  # merge_strategy: :first_in,  # First to complete wins
  # merge_strategy: :collate,   # Conflicts become arrays
  # merge_strategy: :disjoint,  # Error if operations overlap
  operations: [Op1.new, Op2.new]
)
```

### Pipes

Pipes chain stages together:

```ruby
pipe = Brainpipe::Pipe.new(
  name: :my_pipeline,
  stages: [stage1, stage2, stage3],
  timeout: 30  # Optional timeout in seconds
)

result = pipe.call(input: "data")
```

## Type System

Brainpipe includes a robust type system. Operation subclasses have access to type constants without the `Brainpipe::` prefix:

```ruby
class TypedOperation < Brainpipe::Operation
  reads :name, String
  reads :age, Integer
  reads :active, Boolean                          # Brainpipe::Boolean
  reads :tags, [String]                           # Array of strings
  reads :scores, { String => Integer }            # Hash with typed keys/values
  reads :status, Enum[:active, :inactive]         # Brainpipe::Enum
  reads :value, Union[String, Integer]            # Brainpipe::Union
  reads :maybe, Optional[String]                  # Brainpipe::Optional (nil allowed)
  reads :anything, Any                            # Brainpipe::Any
  reads :photo, Image                             # Brainpipe::Image

  sets :result, { name: String, count: Integer }  # Object structure
end
```

## Built-in Operations

### Link

Copy, move, set, or delete properties:

```ruby
Brainpipe::Operations::Link.new(
  options: {
    copy: { source_field: :target_field },     # Copy value
    move: { old_name: :new_name },             # Rename/move property
    set: { new_field: "constant value" },      # Set constant
    delete: [:unwanted_field]                  # Remove properties
  }
)
```

In YAML config:

```yaml
- type: Link
  options:
    copy:
      product: product_name
    move:
      old_key: new_key
    set:
      currency: "USD"
    delete:
      - temp_field
```

### Explode

Split array properties into multiple namespaces (for parallel processing):

```ruby
Brainpipe::Operations::Explode.new(
  options: {
    split: {
      items: :item,        # Array field => singular field name
      prices: :price
    }
  }
)
```

Input: `{ items: ["a", "b"], prices: [10, 20] }`
Output: `[{ item: "a", price: 10 }, { item: "b", price: 20 }]`

### Collapse

Merge multiple namespaces back into arrays:

```ruby
Brainpipe::Operations::Collapse.new(
  options: {
    merge: {
      item: :collect,      # Collect all values into array
      quantity: :sum,      # Sum numeric values
      currency: :equal     # Assert all values are equal, keep one
    }
  }
)
```

Strategies: `:collect` (array), `:sum` (add numbers), `:equal` (assert same value)

### Filter

Filter namespaces by condition:

```ruby
# Filter by field value
Brainpipe::Operations::Filter.new(
  options: { field: :status, value: "active" }
)

# Filter with custom condition
Brainpipe::Operations::Filter.new(
  options: { condition: ->(ns) { ns[:score] > 50 } }
)
```

### Merge

Combine multiple fields:

```ruby
Brainpipe::Operations::Merge.new(
  options: {
    sources: [:first_name, :last_name],
    target: :full_name,
    target_type: String,
    combiner: ->(first, last) { "#{first} #{last}" },
    delete_sources: false
  }
)
```

### Log

Debug logging:

```ruby
Brainpipe::Operations::Log.new(
  options: { fields: [:name, :status], message: "Processing", level: :info }
)
```

### LlmCall

Generic LLM calls with prompt templates (Mustache format):

```yaml
- type: LlmCall
  model: openai
  options:
    capability: text_to_text
    prompt_file: prompts/summarize.mustache
    inputs:
      document: String
    outputs:
      summary: String
```

The prompt file uses Mustache templating with access to namespace fields.

## BAML Integration

Brainpipe integrates with [BAML](https://github.com/BoundaryML/baml) for type-safe LLM function calls.

In YAML config:

```yaml
- type: Baml
  model: openai
  options:
    function: ExtractEntities
    inputs:
      text: document           # Map namespace field to BAML input
    outputs:
      entities: extracted      # Map BAML output to namespace field
```

Programmatically:

```ruby
Brainpipe::Operations::Baml.new(
  model: my_model,
  options: {
    function: :ExtractEntities,
    inputs: { text: :document },
    outputs: { entities: :extracted }
  }
)
```

## Observability

### Debug Mode

Enable debug logging:

```ruby
pipe = Brainpipe::Pipe.new(
  name: :my_pipe,
  stages: [...],
  debug: true
)
```

### Metrics Collector

Implement custom metrics collection:

```ruby
class MyMetrics < Brainpipe::Observability::MetricsCollector
  def operation_started(operation_class:, namespace:, stage:, pipe:)
    # Track operation start
  end

  def operation_completed(operation_class:, namespace:, duration_ms:, stage:, pipe:)
    # Track operation completion
  end

  def operation_failed(operation_class:, namespace:, error:, duration_ms:, stage:, pipe:)
    # Track operation failure
  end

  def pipe_completed(pipe:, input:, output:, duration_ms:, operations_count:)
    # Track pipeline completion
  end
end

Brainpipe.configure do |config|
  config.metrics_collector = MyMetrics.new
end
```

## Error Handling

### Per-Operation Error Handling

```ruby
class ResilientOperation < Brainpipe::Operation
  reads :input, String
  sets :output, String

  ignore_errors true  # Ignore all errors

  # Or with a condition:
  ignore_errors do |error|
    error.is_a?(NetworkError)
  end

  execute do |ns|
    { output: risky_operation(ns[:input]) }
  end
end
```

### Timeouts

```ruby
# Pipe-level timeout
pipe = Brainpipe::Pipe.new(
  name: :timed,
  stages: [...],
  timeout: 60
)

# Stage-level timeout
stage = Brainpipe::Stage.new(
  name: :quick,
  mode: :merge,
  operations: [...],
  timeout: 10
)

# Operation-level timeout
class QuickOp < Brainpipe::Operation
  timeout 5
  # ...
end
```

## Configuration

### Full Configuration Example

```ruby
Brainpipe.configure do |config|
  # Path to YAML configuration files
  config.config_path = "config/brainpipe"

  # Enable debug mode globally
  config.debug = true

  # Set metrics collector
  config.metrics_collector = MyMetrics.new

  # Configure thread pool
  config.max_threads = 10
  config.thread_pool_timeout = 60

  # Secret resolution for API keys
  config.secret_resolver = ->(ref) { MySecretStore.get(ref) }

  # Add autoload paths for operations
  config.autoload_path "app/operations"
  config.autoload_path "lib/operations"

  # Register operations explicitly
  config.register_operation :my_op, MyOperation

  # Define models
  config.model :gpt4 do
    provider :openai
    model "gpt-4"
    capabilities :text_to_text, :text_image_to_text
    api_key "${OPENAI_API_KEY}"
    options({ temperature: 0.7 })
  end
end

# Load configuration and pipes
Brainpipe.load!

# Access loaded pipes and models
pipe = Brainpipe.pipe(:my_pipeline)
model = Brainpipe.model(:gpt4)
```

## Rails Integration

Brainpipe includes a Rails engine that auto-configures everything.

### Setup

Add to your Gemfile:

```ruby
gem 'brainpipe'
```

The railtie automatically:
- Sets `config_path` to `config/brainpipe/`
- Adds `app/operations/` and `app/pipelines/` to autoload paths
- Enables debug mode in development
- Reloads pipelines on code changes in development

### Configuration

Customize in `config/initializers/brainpipe.rb`:

```ruby
Rails.application.config.brainpipe.tap do |config|
  config.config_path = "config/brainpipe"  # Default
  config.debug = true
  config.expose_pipes = :all               # Or array of pipe names
  config.autoload_paths << "lib/operations"
end
```

### Custom Operations

Place custom operations in `app/operations/`:

```ruby
# app/operations/summarize_operation.rb
class SummarizeOperation < Brainpipe::Operation
  reads :text, String
  sets :summary, String

  execute do |ns|
    { summary: "Summary: #{ns[:text]}" }
  end
end
```

Reference in pipeline configs by class name:

```yaml
# config/brainpipe/pipes/my_pipe.yml
stages:
  - name: summarize
    mode: merge
    operations:
      - type: SummarizeOperation
```

## Error Classes

- `Brainpipe::ConfigurationError` - Configuration problems
- `Brainpipe::InvalidYAMLError` - Invalid YAML syntax
- `Brainpipe::MissingOperationError` - Referenced operation not found
- `Brainpipe::MissingModelError` - Referenced model not found
- `Brainpipe::MissingPipeError` - Referenced pipe not found
- `Brainpipe::CapabilityMismatchError` - Model lacks required capability
- `Brainpipe::IncompatibleStagesError` - Stage outputs don't match next stage inputs
- `Brainpipe::ExecutionError` - Runtime execution error
- `Brainpipe::TimeoutError` - Operation/stage/pipe timeout
- `Brainpipe::EmptyInputError` - Empty input to stage/pipe
- `Brainpipe::ContractViolationError` - Operation contract violation
- `Brainpipe::PropertyNotFoundError` - Required property missing
- `Brainpipe::TypeMismatchError` - Value doesn't match declared type
- `Brainpipe::TypeConflictError` - Parallel operations declare conflicting types

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

### Running Tests

```bash
bundle exec rspec
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/kenmiller/brainpipe.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
