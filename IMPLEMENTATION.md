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

## Phase 12: Built-in Operations

**Goal:** Ship useful operations out of the box.

**Components:**
- `lib/brainpipe/operations/transform.rb`
- `lib/brainpipe/operations/filter.rb`
- `lib/brainpipe/operations/merge.rb`
- `lib/brainpipe/operations/log.rb`

**Testing:**
- Each operation's specific behavior
- Property declarations
- Integration in pipes

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
