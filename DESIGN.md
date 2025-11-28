# Brainpipe Technical Design

## Overview

This document covers implementation details and DSL design for Brainpipe.

---

## Operation DSL

Operations can be created by hand (any class satisfying the interface), but an ActiveRecord-style DSL makes common cases easy.

### Hand-Rolled Operation

```ruby
class MyOperation
  def self.reads = { input_text: String }
  def self.sets = { output_text: String }
  def self.deletes = []
  def self.required_model = nil  # or :text_to_text, etc.

  def initialize(model: nil, options: {})
    @model = model
    @options = options
  end

  def create
    # Return a callable that receives array of namespaces, returns array of namespaces
    ->(namespaces) {
      namespaces.map do |ns|
        ns.merge(output_text: transform(ns[:input_text]))
      end
    }
  end

  private

  def transform(input)
    # execution logic
  end
end
```

### DSL-Based Operation

```ruby
# Shortcut for simple cases - block is called per-namespace automatically
class SummarizeText < Brainpipe::Operation
  reads :input_text, String
  sets :summary, String

  execute do |ns|
    # Block receives single namespace, framework handles array iteration
    ns.merge(summary: ns[:input_text].split.first(10).join(" ") + "...")
  end
end

# Full control via create method
class ComplexOperation < Brainpipe::Operation
  reads :input, String
  sets :output, String

  def create
    # Must handle array of namespaces explicitly
    ->(namespaces) {
      namespaces.map { |ns| ns.merge(output: transform(ns[:input])) }
    }
  end
end
```

The DSL provides `reads`, `sets`, `deletes`, `requires_model`, `ignore_errors` class methods. Use `execute do |ns|` for simple per-namespace logic (framework wraps in array handling) or override `create` for full control over array processing.

### Operations Requiring Models

Operations that need an LLM declare the capability they require, not a specific model:

```ruby
class GenerateImage < Brainpipe::Operation
  reads :prompt, String
  sets :image, Brainpipe::Types::Image

  requires_model :text_to_image  # declares needed capability

  execute do |ns|
    result = model.generate(ns[:prompt])
    ns.merge(image: result)
  end
end

class DescribeImage < Brainpipe::Operation
  reads :image, Brainpipe::Types::Image
  sets :description, String

  requires_model :image_to_text

  execute do |ns|
    result = model.describe(ns[:image])
    ns.merge(description: result)
  end
end
```

The `model` accessor is available within the execute block when `requires_model` is declared. The actual model config is wired up in the pipe YAML, not baked into the operation class.

### Property Type Declarations

**Basic types:**
```ruby
reads :name, String
reads :count, Integer
reads :score, Float
reads :active, Boolean
reads :key, Symbol
```

**Arrays:**
```ruby
reads :tags, [String]                          # array of strings
reads :records, [{ id: Integer, name: String }]  # array of objects
```

**Hashes with arbitrary keys:**
```ruby
reads :scores, { String => Integer }           # "player1" => 100
reads :metadata, { Symbol => String }
```

**Object structures:**
```ruby
reads :user, {
  id: Integer,
  name: String,
  email: String,
  address: {
    city: String,
    zip: String
  }
}
```

**Optional fields** (may be absent or nil):
```ruby
reads :config, {
  name: String,          # required
  nickname?: String,     # optional (? shortcut)
  bio?: String
}
```

**No type = any:**
```ruby
reads :payload                      # no type means any value allowed
sets :result                        # same for sets
```

**Type modifiers** (provided by Brainpipe, available without module path in DSL):
```ruby
Any                                 # explicit any (for nested use)
Optional[String]                    # may be absent or nil
Enum['draft', 'published', 'archived']  # must be one of these values
Union[String, Integer]              # either type allowed
```

Use `Any` inside complex types where omitting isn't possible:
```ruby
reads :flexible, { String => Any }  # hash with string keys, any values
reads :mixed, [Any]                 # array of anything
```

**Composable example:**
```ruby
reads :records, [{
  id: Integer,
  status: Enum['draft', 'published'],
  tags?: [String],
  metadata?: { String => Union[String, Integer] }
}]
```

**Reusable type constants:**
```ruby
UserType = {
  id: Integer,
  name: String,
  email?: String
}

reads :author, UserType
reads :reviewers, [UserType]
```

Runtime validation checks structure recursively and raises `TypeMismatchError` with path to violation (e.g., `"records[2].tags[0] expected String, got Integer"`).

### Error Handling

Operations can declare error handling behavior:

```ruby
class RiskyOperation < Brainpipe::Operation
  reads :input, String
  sets :output, String

  ignore_errors true  # continue pipe on failure, skip setting output

  execute do |ns|
    ns.merge(output: risky_call(ns[:input]))
  end
end

class ConditionalErrorHandling < Brainpipe::Operation
  reads :input, String
  sets :output, String

  ignore_errors do |error, namespace|
    error.is_a?(RateLimitError)  # only ignore rate limits
  end

  execute do |ns|
    ns.merge(output: api_call(ns[:input]))
  end
end
```

When an error is ignored, the operation's `sets` are not applied and the namespace passes through unchanged.

---

## Pre-Made Operations

Common operations provided out of the box:

### BAML Operations

```ruby
class CallBAML < Brainpipe::Operations::BAML
  function :ExtractResume  # BAML function name
  reads :resume_text, String
  sets :resume, Types::Resume
end
```

### Utility Operations

- `Brainpipe::Operations::Transform` - Map/transform properties
- `Brainpipe::Operations::Filter` - Conditional pass-through
- `Brainpipe::Operations::Merge` - Combine properties
- `Brainpipe::Operations::Log` - Debug logging

---

## Configuration

### Directory Structure

```
<PROJECT_ROOT>/
├── config/
│   └── brainpipe/
│       ├── config.yml           # global config (models, defaults)
│       └── pipes/
│           ├── my-api.yml       # pipe definitions
│           └── another-pipe.yml
```

### Config DSL (Ruby)

```ruby
Brainpipe.configure do |c|
  c.config_path = "config/brainpipe"  # default
  c.debug = true
  c.metrics_collector = MyMetricsCollector.new

  c.load_config! # reads the config file -- otherwise it happens at the end of the block

  c.model :default do |m|
    m.provider = :openai
    m.model = "gpt-4o"
    m.temperature = 0.7
    m.api_key = ENV["OPENAI_API_KEY"]
  end

  c.model :fast do |m|
    m.provider = :anthropic
    m.model = "claude-3-haiku"
    m.api_key = "${ANTHROPIC_API_KEY}"  # env var reference
  end
end
```

### YAML Config (config.yml)

```yaml
debug: false

models:
  default:
    provider: openai
    model: gpt-4o
    capabilities:
      - text_to_text
    options:
      temperature: 0.7
      api_key: ${OPENAI_API_KEY}

  vision:
    provider: openai
    model: gpt-4o
    capabilities:
      - text_to_text
      - image_to_text      # vision
      - text_image_to_text # directed image editing
    options:
      api_key: ${OPENAI_API_KEY}

  image_gen:
    provider: openai
    model: dall-e-3
    capabilities:
      - text_to_image
    options:
      api_key: ${OPENAI_API_KEY}

  fast:
    provider: anthropic
    model: claude-3-haiku
    capabilities:
      - text_to_text
    options:
      api_key: ${ANTHROPIC_API_KEY}
```

### Model Capabilities

Standard capability identifiers:

| Capability           | Input        | Output | Examples            |
|----------------------|--------------|--------|---------------------|
| `text_to_text`       | Text         | Text   | Chat, completion    |
| `text_to_image`      | Text         | Image  | DALL-E, Midjourney  |
| `image_to_text`      | Image        | Text   | Vision models       |
| `image_analyze`      | Text + Image | Text   | Vision with context |
| `image_edit`         | Text + Image | Image  | Vision + Image Gen  |
| `text_to_audio`      | Text         | Audio  | TTS                 |
| `audio_to_text`      | Audio        | Text   | transcription       |
| `embedding`          | Text         | Vector | Embedding models    |

### Pipe Definition (pipes/my-api.yml)

```yaml
name: my-api

stages:
  - name: extract
    mode: merge
    operations:
      - type: CallBAML
        model: default
        options:
          function: ExtractData

  - name: process
    mode: fan_out
    operations:
      - type: SummarizeText
        model: fast
      - type: GenerateImage
        model: image_gen
        options:
          size: 1024x1024

  - name: validate
    mode: merge
    operations:
      - type: ValidateData    # no model needed

  - name: combine
    mode: merge
    operations:
      - type: AggregateResults
```

- `type`: operation class (required)
- `model`: named model config (required if operation declares `requires_model`)
- `options`: additional operation-specific configuration
- `ignore_errors`: override operation's error handling (optional)

---

## Loading and Execution

```ruby
# Load all configs (reads config/brainpipe/**)
Brainpipe.load!

# Get a pipe (fully configured at load time)
pipe = Brainpipe.pipe(:my_api)

# Inspect interface
pipe.inputs   # => { input_text: String }
pipe.outputs  # => { result: Types::Result }

# Execute - just pass data, everything else is configured
result = pipe.call(input_text: "...")
```

---

## Design Decisions

### Operation Registration

**Built-in operations** ship with the gem and are always available under `Brainpipe::Operations::*`:
- `Brainpipe::Operations::BAML` - BAML function wrapper
- `Brainpipe::Operations::Transform` - property mapping
- `Brainpipe::Operations::Filter` - conditional pass-through
- `Brainpipe::Operations::Merge` - combine properties
- `Brainpipe::Operations::Log` - debug logging
- etc.

**User-defined operations** are auto-discovered via Zeitwerk from `app/operations/` (Rails) or `lib/operations/`:

```
app/operations/
├── summarize_text.rb      → SummarizeText
├── extract/
│   └── resume.rb          → Extract::Resume
```

Config API for additional paths or overrides:

```ruby
Brainpipe.configure do |c|
  # Add custom autoload path
  c.autoload_path "lib/my_operations"

  # Explicit registration (overrides autoload or built-ins)
  c.register_operation :summarize, MyCustomSummarizer

  # Alias an operation
  c.register_operation :summarise, SummarizeText
end
```

In pipe YAML, reference by class name:
```yaml
operations:
  - type: Brainpipe::Operations::BAML   # built-in
  - type: SummarizeText                  # user-defined
```

### Executor Pattern
Operations are factories with a `create` method that returns a callable:

```ruby
class SummarizeText < Brainpipe::Operation
  reads :input_text, String
  reads :context, String, optional: true  # optional read
  sets :summary, String

  def create
    # Returns a callable (Proc, lambda, or object with #call)
    # Callable ALWAYS receives array of namespaces, returns array of namespaces
    ->(namespaces) {
      namespaces.map do |ns|
        text = ns[:input_text]
        context = ns[:context]  # nil if not present (optional)

        result = do_summarization(text, context)
        ns.merge(summary: result)
      end
    }
  end
end
```

- `create` returns a callable
- Callable **always** receives array of namespaces (even if single element)
- Callable **always** returns array of namespaces (same count as input)
- Runtime validates contract: declared reads/sets/deletes
- Supports `optional: true` for reads/sets/deletes

### Optional Property Behavior

- **Optional read**: Returns `nil` if property not present in namespace
- **Optional set**: No `ContractViolationError` if property not set in output
- **Optional delete**: No error if property wasn't present to delete

### Capability Validation
- At config load: validate model config has capabilities operation requires
- Out of scope: validating model can actually perform claimed capabilities (trust the config)

---

## Gem File Structure

```
lib/
├── brainpipe.rb                      # Main entry point, public API
└── brainpipe/
    ├── version.rb
    ├── configuration.rb              # Config DSL and storage
    ├── loader.rb                     # YAML loading, Zeitwerk setup
    │
    ├── pipe.rb                       # Pipe class
    ├── stage.rb                      # Stage class
    ├── operation.rb                  # Base operation class with DSL
    ├── executor.rb                   # Executor wrapper with contract validation
    ├── namespace.rb                  # Property namespace
    │
    ├── model_config.rb               # Model configuration
    ├── model_registry.rb             # Named model storage
    ├── capabilities.rb               # Capability constants and validation
    │
    ├── operations/                   # Built-in operations
    │   ├── baml.rb
    │   ├── transform.rb
    │   ├── filter.rb
    │   ├── merge.rb
    │   └── log.rb
    │
    ├── types/                        # Built-in types
    │   ├── image.rb
    │   ├── audio.rb
    │   └── embedding.rb
    │
    ├── observability/
    │   ├── debug.rb                  # Debug output
    │   └── metrics_collector.rb      # Metrics interface
    │
    └── errors.rb                     # Error classes
```

---

## Core Class Definitions

### Brainpipe (Module)

Main entry point and public API.

```ruby
module Brainpipe
  class << self
    def configure(&block)
    def load!
    def pipe(name)
    def model(name)
    def reset!  # for testing
  end
end
```

### Brainpipe::Configuration

```ruby
class Configuration
  attr_accessor :config_path, :debug, :metrics_collector
  attr_reader :models, :pipes

  def model(name, &block)
  def autoload_path(path)
  def register_operation(name, klass)
  def load_config!
end
```

### Brainpipe::Pipe

```ruby
class Pipe
  attr_reader :name, :stages, :inputs, :outputs

  def initialize(name:, stages:)
  def call(properties)          # Execute with input properties
  def validate!                 # Validate stage compatibility
end
```

### Brainpipe::Stage

```ruby
class Stage
  attr_reader :name, :mode, :operations, :merge_strategy

  MODES = [:merge, :fan_out, :batch].freeze
  MERGE_STRATEGIES = [:last_in, :first_in, :collate, :disjoint].freeze

  def initialize(name:, mode:, operations:, merge_strategy: :last_in)
  def call(namespace_array)     # Execute stage
  def inputs                    # Aggregated from operations
  def outputs                   # Aggregated from operations
  def validate!                 # For disjoint strategy, verify no overlapping sets
end
```

### Brainpipe::Operation

Base class with DSL.

```ruby
class Operation
  class << self
    # Class-level declarations (static, for simple operations)
    def reads(name, type, optional: false)
    def sets(name, type, optional: false)
    def deletes(name)
    def requires_model(capability)
    def ignore_errors(bool_or_block)
    def execute(&block)
  end

  def initialize(model: nil, options: {})
  def create                    # Returns callable, override or use execute DSL
  def model                     # Accessor for model (available in execute block)

  # Instance-level property introspection (FINAL resolution - used for validation)
  def declared_reads            # Returns { name: Type, ... }
  def declared_sets             # Returns { name: Type, ... }
  def declared_deletes          # Returns [name, ...]
  def required_model_capability # Returns capability symbol or nil
  def error_handler             # Returns nil, true, or Proc
end
```

**Instance-level resolution**: Property declarations are resolved on the *instance* after initialization. This enables:

```ruby
# Dynamic properties based on options
class RenameField < Brainpipe::Operation
  def initialize(model: nil, options: {})
    super
    @from = options[:from]
    @to = options[:to]
  end

  def declared_reads = { @from => T.untyped }
  def declared_sets = { @to => T.untyped }
  def declared_deletes = [@from]

  def create
    from, to = @from, @to
    ->(namespaces) {
      namespaces.map { |ns| ns.delete(from).merge(to => ns[from]) }
    }
  end
end

# BAML operation introspects function signature
class BAMLCall < Brainpipe::Operations::BAML
  def initialize(model: nil, options: {})
    super
    @function = BAML.function(options[:function])
  end

  def declared_reads = @function.input_schema
  def declared_sets = @function.output_schema
end
```

Class-level DSL (`reads`, `sets`, etc.) provides defaults; instance methods override when dynamic behavior is needed.

### Brainpipe::Namespace

Immutable property container with type checking.

```ruby
class Namespace
  def initialize(properties = {})
  def [](key)
  def merge(properties)         # Returns new Namespace
  def delete(*keys)             # Returns new Namespace
  def to_h
  def keys
end
```

### Brainpipe::Executor

Wraps callable with contract validation.

```ruby
class Executor
  def initialize(callable, operation_class:, debug: false)
  def call(namespace)

  private
  def validate_reads!(namespace)
  def validate_writes!(before, after)
  def validate_deletes!(before, after)
  def handle_error(error, namespace)  # Uses operation's error_handler
end
```

### Brainpipe::ModelConfig

```ruby
class ModelConfig
  attr_reader :name, :provider, :model, :capabilities, :options

  def initialize(name:, provider:, model:, capabilities:, options: {})
  def has_capability?(capability)
  def to_baml_client_registry    # Convert for BAML
end
```

---

## Error Types

```ruby
module Brainpipe
  class Error < StandardError; end

  # Configuration errors (raised at load time)
  class ConfigurationError < Error; end
  class InvalidYAMLError < ConfigurationError; end
  class MissingOperationError < ConfigurationError; end
  class MissingModelError < ConfigurationError; end
  class CapabilityMismatchError < ConfigurationError; end
  class IncompatibleStagesError < ConfigurationError; end

  # Runtime errors
  class ExecutionError < Error; end
  class TimeoutError < ExecutionError; end
  class EmptyInputError < ExecutionError; end
  class ContractViolationError < ExecutionError; end
  class PropertyNotFoundError < ContractViolationError; end
  class TypeMismatchError < ContractViolationError; end
  class UnexpectedPropertyError < ContractViolationError; end
  class UnexpectedDeletionError < ContractViolationError; end
  class OutputCountMismatchError < ContractViolationError; end
end
```

---

## Dependencies

### Required
- `zeitwerk` - Autoloading
- `sorbet-runtime` - Runtime type checking (T::Struct, etc.)
- `concurrent-ruby` - Thread pool for fan-out

### Optional
- `baml` - BAML integration (runtime dependency)

### Development
- `rspec` - Testing
- `sorbet` - Static type checking
- `rubocop` - Linting

---

## Data Flow

### Stage Modes Explained

**Merge Mode**: Combine all incoming namespaces into one (last wins), then run operations.
```
Input: [ns1, ns2, ns3]  →  merge (last wins)  →  ns  →  [Op A, Op B] (parallel)  →  [ns']
```

**Fan-Out Mode**: Each incoming namespace gets its own operation instance(s), run concurrently.
```
Input: [ns1, ns2, ns3]  →  fork  →  [Op A(ns1), Op A(ns2), Op A(ns3)]  →  [ns1', ns2', ns3']
                                    (concurrent execution)
```

**Batch Mode**: Pass entire array to operations, they handle iteration internally.
```
Input: [ns1, ns2, ns3]  →  [Op A]([ns1, ns2, ns3])  →  [ns1', ns2', ...]
```

### Multiple Operations in a Stage

**All operations within a stage run in parallel**, regardless of mode. Sequential processing requires separate stages.

```
Stage with [Op A, Op B, Op C]:

  Non fan-out modes:
    namespace → fork → [Op A(ns), Op B(ns), Op C(ns)] → merge results
                       (all run concurrently on same input)

  Fan-out mode:
    [ns1, ns2] → [Op A(ns1), Op B(ns1), Op C(ns1),   → [ns1', ns2']
                  Op A(ns2), Op B(ns2), Op C(ns2)]
                 (N × M instances, all concurrent)
```

**Merge strategy** for parallel operation results is configured per-stage:

```yaml
stages:
  - name: enrich
    mode: merge
    merge_strategy: last_in    # default: last to complete wins
    operations:
      - type: EnrichA
      - type: EnrichB
```

Available strategies:
- `last_in` (default): Last operation to complete wins for conflicting properties
- `first_in`: First operation to complete wins
- `collate`: Conflicting properties become arrays containing all values
- `disjoint`: Validate at config load that operations have no overlapping `sets` (error if conflict possible)

### Example Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                           PIPE                                   │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐      │
│  │ Stage 1 │───▶│ Stage 2 │───▶│ Stage 3 │───▶│ Stage 4 │      │
│  │ (batch) │    │(fan_out)│    │(fan_out)│    │ (merge) │      │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘      │
└─────────────────────────────────────────────────────────────────┘

Input: Single Namespace { items: [a, b, c, d, e] }
       │
       ▼
┌──────────────┐
│   Stage 1    │  mode: batch
│  [Splitter]  │  Takes array, outputs multiple namespaces
└──────────────┘  Output: [ns1, ns2, ns3, ns4, ns5]  (one per item)
       │
       ▼
┌──────────────┐
│   Stage 2    │  mode: fan_out, single operation
│  [ProcessOp] │  5 instances created, one per namespace
└──────────────┘  Runs concurrently: [Op(ns1), Op(ns2), Op(ns3), Op(ns4), Op(ns5)]
       │          Output: [ns1', ns2', ns3', ns4', ns5']
       ▼
┌──────────────┐
│   Stage 3    │  mode: fan_out, multiple operations
│[EnrichA,     │  Each namespace gets both ops in parallel
│ EnrichB]     │  5 × 2 = 10 operation instances, all concurrent
└──────────────┘  Results merged per-namespace
       │          Output: [ns1'', ns2'', ns3'', ns4'', ns5'']
       ▼
┌──────────────┐
│   Stage 4    │  mode: merge
│ [Aggregator] │  Merges all namespaces, runs aggregation
└──────────────┘
       │
       ▼
Output: Single Namespace { result: "..." }
```

### Key Points

1. **Fan-out** creates **N × M** operation instances (N namespaces × M operations)
2. **All operations in a stage run in parallel** - use separate stages for sequential processing
3. **Merge mode** collapses multiple namespaces into one before running operations
4. **Batch mode** passes the entire array to operations that handle iteration internally

---

## Public API Summary

```ruby
# Configuration
Brainpipe.configure do |c|
  c.config_path = "config/brainpipe"
  c.debug = true
  c.autoload_path "app/operations"
  c.register_operation :custom, MyCustomOp
end

# Loading
Brainpipe.load!

# Execution
pipe = Brainpipe.pipe(:my_api)
pipe.inputs   # => { input_text: String }
pipe.outputs  # => { result: String }
result = pipe.call(input_text: "hello")

# Model access (for programmatic use)
model = Brainpipe.model(:default)
model.capabilities  # => [:text_to_text]

# Operation definition
class MyOp < Brainpipe::Operation
  reads :input, String
  sets :output, String
  requires_model :text_to_text

  execute do |ns|
    ns.merge(output: model.complete(ns[:input]))
  end
end
```

---

## Parallel Error Handling

When an operation fails in a parallel stage:

1. **Other operations in the stage are allowed to complete** (not cancelled)
2. All results (success and failure) are collected for debugging/recording
3. After all operations complete, the first non-ignored error is raised
4. Subsequent stages do not execute

This allows metrics collectors and debug tooling to capture full execution state even on failure.

---

## Timeout Enforcement

Timeouts are optional at each config level:

```yaml
name: my-api
timeout: 300  # pipe-level timeout (seconds)

stages:
  - name: extract
    timeout: 60  # stage-level timeout
    operations:
      - type: CallBAML
        model: default
        timeout: 30  # operation-level timeout
```

**Enforcement:**
- **Pipe timeout**: Wraps entire `Pipe#call`; raises `TimeoutError`
- **Stage timeout**: Wraps `Stage#call`; cancels in-flight operations if exceeded
- **Operation timeout**: Per-executor wrapper

Inner timeouts are implicitly clamped by outer timeouts.

---

## Thread Safety

- **ModelConfig**: Immutable after construction, safe to share across threads
- **Namespace**: Designed for copy-on-write semantics; each thread gets its own copy
- **BAML clients**: Assumed thread-safe (BAML's responsibility)
- **Operation factories**: Instantiated once, `create` called per-execution to produce isolated executors
- **Executors**: Fresh instance per execution, no shared mutable state

The `concurrent-ruby` thread pool handles fan-out parallelism. Each concurrent branch receives:
- Its own Namespace copy
- Its own Executor instance (from `operation.create`)
- Shared (immutable) ModelConfig reference

---

## Secret Store Integration

Model configs support environment variables by default (`${ENV_VAR}`), but a custom secret resolver can be configured:

```ruby
Brainpipe.configure do |c|
  c.secret_resolver = ->(ref) {
    # ref is the string after the prefix, e.g., "my-api-key"
    Vault.read("secret/brainpipe/#{ref}")
  }
end
```

In YAML, reference secrets with `secret://`:

```yaml
models:
  default:
    provider: openai
    model: gpt-4o
    options:
      api_key: secret://openai-api-key
```

Resolution order:
1. `${ENV_VAR}` → resolved from environment
2. `secret://ref` → resolved via `secret_resolver` (error if not configured)
3. Plain string → used as-is (not recommended for secrets)

---

## Thread Pool Configuration

Fan-out parallelism uses `concurrent-ruby` thread pools. Configure via:

```ruby
Brainpipe.configure do |c|
  c.max_threads = 10          # Max concurrent operations (default: processor count)
  c.thread_pool_timeout = 5   # Seconds to wait for thread availability
end
```

For extreme fan-out scenarios (e.g., 1000 namespaces), operations are queued and processed as threads become available.

---

## Configuration Precedence

Configuration sources are applied in order, **last wins**:

1. Built-in defaults
2. YAML config file (`config/brainpipe/config.yml`)
3. Ruby DSL (`Brainpipe.configure do ... end`)

Use `load_config!` within the configure block to control when YAML is loaded:

```ruby
Brainpipe.configure do |c|
  # These apply BEFORE yaml
  c.debug = false

  c.load_config!  # Load YAML here

  # These apply AFTER yaml (override it)
  c.debug = true
  c.model :default do |m|
    m.model = "gpt-4o-mini"  # Override YAML's model
  end
end
```

If `load_config!` is not called explicitly, it happens at the end of the configure block.

Zeitwerk autoloading also respects this order - paths added via `autoload_path` are processed after built-in operations but can be overridden by explicit `register_operation` calls.

---

## Metrics Collector Interface

Custom metrics collectors must implement:

```ruby
class MyMetricsCollector
  # Called when an operation starts
  def operation_started(operation_class:, namespace:, stage:, pipe:)
  end

  # Called when an operation completes successfully
  def operation_completed(operation_class:, namespace:, duration_ms:, stage:, pipe:)
  end

  # Called when an operation fails
  def operation_failed(operation_class:, namespace:, error:, duration_ms:, stage:, pipe:)
  end

  # Called for model/LLM interactions (BAML integration)
  def model_called(model_config:, input:, output:, tokens_in:, tokens_out:, duration_ms:)
  end

  # Called when a pipe execution completes
  def pipe_completed(pipe:, input:, output:, duration_ms:, operations_count:)
  end
end
```

All methods are optional - implement only what you need. A no-op default is used for unimplemented methods.

---

## Open Design Questions

None currently - all major decisions resolved.
