# Brainpipe Implementation Plan

## Phase 1: Core Foundation

**Goal:** Basic infrastructure that everything else depends on.

**Components:**
- `lib/brainpipe.rb` - Module entry point with `configure`, `load!`, `pipe`, `model`, `reset!`
- `lib/brainpipe/version.rb` - Already exists
- `lib/brainpipe/errors.rb` - All error classes
- `lib/brainpipe/namespace.rb` - Immutable property container with `[]`, `merge`, `delete`, `to_h`, `keys`

**Testing:**
- Namespace: immutability, merge semantics, delete behavior
- Errors: verify inheritance hierarchy

**Why first:** Namespace is the data structure everything operates on. Errors are referenced everywhere.

---

## Phase 2: Type System

**Goal:** Property type declarations and runtime validation.

**Components:**
- `lib/brainpipe/types.rb` - Type constants (`Any`, `Optional`, `Enum`, `Union`)
- `lib/brainpipe/type_checker.rb` - Recursive structural validation

**Testing:**
- Basic types: `String`, `Integer`, `Float`, `Boolean`, `Symbol`
- Arrays: `[String]`, `[{id: Integer}]`
- Hashes: `{ String => Integer }`
- Object structures with nesting
- Optional fields (`?` suffix)
- Type modifiers: `Any`, `Optional[T]`, `Enum[...]`, `Union[T1, T2]`
- Error messages with path to violation (`"records[2].tags[0] expected String, got Integer"`)

**Why second:** Operations need types for property declarations. Validation happens at both config-load and runtime.

---

## Phase 3: Operation Base Class

**Goal:** Operation DSL and factory pattern.

**Components:**
- `lib/brainpipe/operation.rb` - Base class with DSL (`reads`, `sets`, `deletes`, `requires_model`, `ignore_errors`, `execute`)

**Testing:**
- DSL declarations at class level
- Instance-level resolution (`declared_reads`, `declared_sets`, `declared_deletes`)
- `execute do |ns|` block form (per-namespace convenience)
- `create` method override (full array control)
- Optional reads/sets
- Dynamic property declarations (override instance methods)

**Why third:** Operations are the unit of work. Need them before stages can orchestrate them.

---

## Phase 4: Executor & Contract Validation

**Goal:** Wrap callables with pre/post validation.

**Components:**
- `lib/brainpipe/executor.rb` - Validates reads before, sets/deletes after, handles errors

**Testing:**
- Validates declared reads exist in namespace
- Validates declared sets appear in output
- Validates declared deletes are removed
- Optional property handling
- Error handler invocation (boolean and proc forms)
- `ContractViolationError` subtypes with useful messages

**Why fourth:** Executor is the runtime enforcement layer. Test it in isolation before integrating with stages.

---

## Phase 5: Model Configuration

**Goal:** Named model configs with capabilities.

**Components:**
- `lib/brainpipe/model_config.rb` - Immutable config holder
- `lib/brainpipe/model_registry.rb` - Named storage and lookup
- `lib/brainpipe/capabilities.rb` - Capability constants and validation

**Testing:**
- Model config creation with provider, model, capabilities, options
- Capability checking (`has_capability?`)
- Registry storage and retrieval
- Environment variable resolution (`${ENV_VAR}`)
- Secret reference parsing (`secret://ref`) - resolution deferred to Phase 9

**Why fifth:** Operations reference models by name. Need registry before configuration loading.

---

## Phase 6: Stage Execution

**Goal:** Stage modes and parallel execution.

**Components:**
- `lib/brainpipe/stage.rb` - Modes (merge, fan_out, batch), parallel ops, merge strategies

**Dependencies:** `concurrent-ruby` for thread pool

**Testing:**
- **Merge mode:** Combines input namespaces, runs ops, outputs single namespace array
- **Fan-out mode:** Each namespace → own executor instance(s), concurrent execution
- **Batch mode:** Entire array passed to operations
- **Parallel operations:** Multiple ops in stage run concurrently
- **Merge strategies:** `last_in`, `first_in`, `collate`, `disjoint`
- Empty input handling (raise error)
- Stage `inputs`/`outputs` aggregation from operations

**Why sixth:** Stages are the orchestration unit. Need operations working first.

---

## Phase 7: Pipe Assembly & Validation

**Goal:** Pipe construction with compatibility validation.

**Components:**
- `lib/brainpipe/pipe.rb` - Stage sequence, input/output advertising, validation

**Testing:**
- Stage compatibility validation at construction
- Input properties from first stage
- Output properties from last stage
- Last stage must be merge mode
- `IncompatibleStagesError` with useful messages
- `pipe.call(properties)` execution flow

**Why seventh:** Pipes compose stages. Need stages working first.

---

## Phase 8: Configuration DSL

**Goal:** Ruby configuration API.

**Components:**
- `lib/brainpipe/configuration.rb` - Config DSL (`config_path`, `debug`, `model`, `autoload_path`, `register_operation`, `secret_resolver`, `max_threads`, `thread_pool_timeout`)

**Testing:**
- Model definition via block
- Operation registration
- Autoload path management
- Secret resolver configuration
- Thread pool settings
- `load_config!` timing control

**Why eighth:** Configuration shapes everything else. Test DSL before YAML loading.

---

## Phase 9: YAML Loading & Autoloading

**Goal:** Load configs from files, auto-discover operations.

**Components:**
- `lib/brainpipe/loader.rb` - YAML parsing, Zeitwerk setup, pipe construction

**Dependencies:** `zeitwerk` for autoloading

**Testing:**
- `config.yml` parsing (models, global settings)
- Pipe YAML parsing (stages, operations, options)
- Operation class resolution (built-in, user-defined, registered)
- Model reference resolution
- Capability validation (operation requires model with capability)
- Secret resolution via configured resolver
- Zeitwerk autoload paths (default + custom)
- Error handling: `InvalidYAMLError`, `MissingOperationError`, `MissingModelError`, `CapabilityMismatchError`

**Why ninth:** Loading ties everything together. Needs all components working.

---

## Phase 10: Timeout & Error Handling

**Goal:** Timeout enforcement and parallel error collection.

**Components:**
- Updates to `Pipe`, `Stage`, `Executor` for timeout wrapping
- Parallel error collection in `Stage`

**Testing:**
- Pipe-level timeout wraps entire execution
- Stage-level timeout cancels in-flight operations
- Operation-level timeout per executor
- `TimeoutError` raised appropriately
- Parallel ops: all complete, errors collected, first non-ignored raised
- Inner timeouts clamped by outer timeouts

**Why tenth:** Timeout is cross-cutting. Easier to add after core flow works.

---

## Phase 11: Observability

**Goal:** Debug output and metrics collection.

**Components:**
- `lib/brainpipe/observability/debug.rb` - Debug output formatting
- `lib/brainpipe/observability/metrics_collector.rb` - Interface and null implementation

**Testing:**
- Debug mode shows operation execution details
- Metrics collector receives expected callbacks
- No-op default for unimplemented methods
- Integration with executor/stage/pipe for callback timing

**Why eleventh:** Observability is additive. Core functionality must work first.

---

## Phase 12: Built-in Operations (Type-Safe)

**Goal:** Ship useful operations that preserve type information through the pipeline.

### Type Flow Mechanism

Operations receive the prefix schema when declaring their contracts. This enables utility operations to look up source field types and propagate them correctly.

**Schema flow rule:**
```
stage_output_schema = prefix_schema - deletes + sets
```

Operations only declare what they explicitly touch; everything else flows through unchanged.

**Method signature change:**
```ruby
# Updated signatures (backward compatible via default param)
def declared_reads(prefix_schema = {})
def declared_sets(prefix_schema = {})
def declared_deletes(prefix_schema = {})
```

### Prerequisites (updates to existing code)

**`lib/brainpipe/operation.rb`:**
- Update `declared_reads`, `declared_sets`, `declared_deletes` to accept `prefix_schema = {}`

**`lib/brainpipe/pipe.rb`:**
- Pass prefix schema during `validate_stage_compatibility!`
- Add `validate_parallel_type_consistency!` for stages with multiple operations

**`lib/brainpipe/stage.rb`:**
- Update `aggregate_reads`/`aggregate_sets` to pass prefix schema to operations

**`lib/brainpipe/errors.rb`:**
- Add `TypeConflictError < ConfigurationError`

### Load-Time Type Conflict Detection

When validating parallel operations in a stage:
1. Collect `declared_sets(prefix_schema)` from all operations
2. For fields set by multiple operations, verify types match
3. Raise `TypeConflictError` if same field has different types

```ruby
def validate_parallel_type_consistency!(operations, prefix_schema)
  all_sets = {}
  operations.each do |op|
    op.declared_sets(prefix_schema).each do |field, type|
      if all_sets[field] && all_sets[field] != type
        raise TypeConflictError,
          "Field '#{field}' set with conflicting types: #{all_sets[field]} vs #{type}"
      end
      all_sets[field] = type
    end
  end
end
```

### Components

**`lib/brainpipe/operations/transform.rb`** - Rename/copy fields with type preservation

```ruby
class Transform < Brainpipe::Operation
  # options: { from: :old_name, to: :new_name, delete_source: true }

  def initialize(model: nil, options: {})
    super
    @from = options[:from]&.to_sym
    @to = options[:to]&.to_sym
    @delete_source = options.fetch(:delete_source, true)
  end

  def declared_reads(prefix_schema = {})
    { @from => prefix_schema[@from] || Any }
  end

  def declared_sets(prefix_schema = {})
    { @to => prefix_schema[@from] || Any }
  end

  def declared_deletes(prefix_schema = {})
    @delete_source ? [@from] : []
  end

  def create
    from, to, delete = @from, @to, @delete_source
    ->(namespaces) {
      namespaces.map do |ns|
        result = ns.merge(to => ns[from])
        delete ? result.delete(from) : result
      end
    }
  end
end
```

**`lib/brainpipe/operations/filter.rb`** - Conditional pass-through (pure passthrough for schema)

```ruby
class Filter < Brainpipe::Operation
  # options: { field: :status, value: "active" }
  #   or:    { condition: ->(ns) { ns[:score] > 0.5 } }

  def initialize(model: nil, options: {})
    super
    @field = options[:field]&.to_sym
    @value = options[:value]
    @condition = options[:condition]
  end

  def declared_reads(prefix_schema = {})
    @field ? { @field => prefix_schema[@field] || Any } : {}
  end

  def declared_sets(prefix_schema = {})
    {}
  end

  def declared_deletes(prefix_schema = {})
    []
  end

  def create
    field, value, condition = @field, @value, @condition
    ->(namespaces) {
      namespaces.select do |ns|
        if condition
          condition.call(ns)
        else
          ns[field] == value
        end
      end
    }
  end
end
```

**`lib/brainpipe/operations/merge.rb`** - Combine multiple fields into one

```ruby
class Merge < Brainpipe::Operation
  # options: { sources: [:first_name, :last_name], target: :full_name,
  #            combiner: ->(vals) { vals.join(" ") },
  #            target_type: String, delete_sources: false }

  def initialize(model: nil, options: {})
    super
    @sources = Array(options[:sources]).map(&:to_sym)
    @target = options[:target]&.to_sym
    @combiner = options[:combiner] || ->(vals) { vals }
    @target_type = options[:target_type] || Any
    @delete_sources = options.fetch(:delete_sources, false)
  end

  def declared_reads(prefix_schema = {})
    @sources.each_with_object({}) { |s, h| h[s] = prefix_schema[s] || Any }
  end

  def declared_sets(prefix_schema = {})
    { @target => @target_type }
  end

  def declared_deletes(prefix_schema = {})
    @delete_sources ? @sources : []
  end

  def create
    sources, target, combiner, delete = @sources, @target, @combiner, @delete_sources
    ->(namespaces) {
      namespaces.map do |ns|
        values = sources.map { |s| ns[s] }
        result = ns.merge(target => combiner.call(values))
        delete ? sources.reduce(result) { |r, s| r.delete(s) } : result
      end
    }
  end
end
```

**`lib/brainpipe/operations/log.rb`** - Debug logging (pure passthrough)

```ruby
class Log < Brainpipe::Operation
  # options: { fields: [:foo, :bar], message: "Debug point", level: :info }

  def initialize(model: nil, options: {})
    super
    @fields = options[:fields]&.map(&:to_sym)
    @message = options[:message]
    @level = options[:level] || :debug
  end

  def declared_reads(prefix_schema = {})
    @fields&.each_with_object({}) { |f, h| h[f] = prefix_schema[f] || Any } || {}
  end

  def declared_sets(prefix_schema = {})
    {}
  end

  def declared_deletes(prefix_schema = {})
    []
  end

  def create
    fields, message, level = @fields, @message, @level
    ->(namespaces) {
      namespaces.each do |ns|
        output = { message: message, namespace_id: ns.object_id }
        output[:fields] = fields.to_h { |f| [f, ns[f]] } if fields
        Brainpipe.logger&.send(level, output)
      end
      namespaces
    }
  end
end
```

### Testing

**Type preservation:**
- Transform renames field, verify output schema has correct type
- Chained transforms (A→B→C) preserve type through chain
- Merge declares explicit target_type, verify it's enforced

**Type conflict detection:**
- Two parallel ops setting same field with same type: OK
- Two parallel ops setting same field with different types: `TypeConflictError` at load time

**Schema flow:**
- Verify `prefix - deletes + sets` calculation
- Fields not touched by operation flow through unchanged

**Each operation:**
- Transform: rename, copy (delete_source: false), type lookup from prefix
- Filter: field/value match, custom condition, returns subset of namespaces
- Merge: multiple sources combined, target_type enforced, optional source deletion
- Log: pure passthrough, no schema changes

**Why twelfth:** Built-ins are conveniences. Core framework must work first.

---

## Phase 13: BAML Integration

**Goal:** First-class BAML support.

**Components:**
- `lib/brainpipe/operations/baml.rb` - BAML function wrapper
- `lib/brainpipe/baml_adapter.rb` - Client registry conversion, function introspection

**Dependencies:** `baml` gem (optional runtime dependency)

**Testing:**
- BAML function wrapping
- Dynamic property declaration from BAML schema
- `to_baml_client_registry` conversion
- Metrics integration for token tracking
- Graceful behavior when BAML not installed

**Why last:** BAML is optional. Everything else must work without it.

---

## Testing Strategy

**Unit tests:** Each component in isolation with mocks/stubs for dependencies

**Integration tests:**
- Simple pipe: single stage, single operation
- Multi-stage pipe: merge → fan_out → merge
- Parallel operations in single stage
- Error propagation and handling
- Timeout behavior
- YAML loading end-to-end

**Fixtures:**
- Sample YAML configs (valid and invalid)
- Sample operations for testing

**Test helpers:**
- Factory methods for namespaces, operations, stages, pipes
- Custom matchers for error types and messages

---

## Dependency Installation Order

1. **Phase 1-5:** No external deps beyond sorbet-runtime
2. **Phase 6:** Add `concurrent-ruby`
3. **Phase 9:** Add `zeitwerk`
4. **Phase 13:** Add `baml` as optional
