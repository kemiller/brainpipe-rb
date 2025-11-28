# Brainpipe Implementation Tasks

## Phase 1: Core Foundation

- [x] Update `lib/brainpipe.rb` with module skeleton
  - [x] `Brainpipe.configure(&block)`
  - [x] `Brainpipe.load!`
  - [x] `Brainpipe.pipe(name)`
  - [x] `Brainpipe.model(name)`
  - [x] `Brainpipe.reset!`
- [x] Create `lib/brainpipe/errors.rb`
  - [x] `Brainpipe::Error` base class
  - [x] Configuration errors: `ConfigurationError`, `InvalidYAMLError`, `MissingOperationError`, `MissingModelError`, `CapabilityMismatchError`, `IncompatibleStagesError`
  - [x] Runtime errors: `ExecutionError`, `TimeoutError`, `EmptyInputError`
  - [x] Contract errors: `ContractViolationError`, `PropertyNotFoundError`, `TypeMismatchError`, `UnexpectedPropertyError`, `UnexpectedDeletionError`, `OutputCountMismatchError`
- [x] Create `lib/brainpipe/namespace.rb`
  - [x] `initialize(properties = {})`
  - [x] `[](key)` - property access
  - [x] `merge(properties)` - returns new Namespace
  - [x] `delete(*keys)` - returns new Namespace
  - [x] `to_h` - hash representation
  - [x] `keys` - property names
  - [x] Ensure immutability (freeze internal hash)
- [x] Write specs for `Namespace`
  - [x] Immutability tests
  - [x] Merge semantics (new instance, original unchanged)
  - [x] Delete behavior
  - [x] Key access
- [x] Write specs for error hierarchy

---

## Phase 2: Type System

- [x] Create `lib/brainpipe/types.rb`
  - [x] `Any` constant
  - [x] `Optional[T]` wrapper
  - [x] `Enum[*values]` wrapper
  - [x] `Union[*types]` wrapper
  - [x] `Boolean` constant (Ruby lacks native Boolean)
- [x] Create `lib/brainpipe/type_checker.rb`
  - [x] `TypeChecker.validate!(value, type, path: "")`
  - [x] Basic type checking: `String`, `Integer`, `Float`, `Symbol`
  - [x] `Boolean` checking (TrueClass/FalseClass)
  - [x] Array type checking: `[String]`
  - [x] Hash with typed keys/values: `{ String => Integer }`
  - [x] Object structure checking: `{ name: String, age: Integer }`
  - [x] Nested structure support
  - [x] Optional field handling (`key?:` suffix detection)
  - [x] `Any` type (always passes)
  - [x] `Optional[T]` handling (nil allowed)
  - [x] `Enum[*values]` validation
  - [x] `Union[*types]` validation
  - [x] Error messages with path: `"records[2].tags[0] expected String, got Integer"`
- [x] Write specs for `TypeChecker`
  - [x] Basic types
  - [x] Arrays of types
  - [x] Hashes with key/value types
  - [x] Object structures
  - [x] Nested structures
  - [x] Optional fields
  - [x] Type modifiers (Any, Optional, Enum, Union)
  - [x] Error message formatting

---

## Phase 3: Operation Base Class

- [x] Create `lib/brainpipe/operation.rb`
  - [x] Class-level DSL methods:
    - [x] `reads(name, type = nil, optional: false)`
    - [x] `sets(name, type = nil, optional: false)`
    - [x] `deletes(name)`
    - [x] `requires_model(capability)`
    - [x] `ignore_errors(bool_or_block)`
    - [x] `execute(&block)`
  - [x] Instance methods:
    - [x] `initialize(model: nil, options: {})`
    - [x] `create` - returns callable
    - [x] `model` - accessor for assigned model
    - [x] `declared_reads` - returns `{ name: type }`
    - [x] `declared_sets` - returns `{ name: type }`
    - [x] `declared_deletes` - returns `[name, ...]`
    - [x] `required_model_capability` - returns symbol or nil
    - [x] `error_handler` - returns nil, true, or Proc
  - [x] `execute` block wrapping (per-namespace iteration)
  - [x] Support for `create` override (full array control)
- [x] Write specs for `Operation`
  - [x] DSL declarations
  - [x] Instance-level resolution
  - [x] `execute` block form
  - [x] `create` override form
  - [x] Optional property declarations
  - [x] Dynamic property declarations (override instance methods)
  - [x] Model requirement declaration

---

## Phase 4: Executor & Contract Validation

- [ ] Create `lib/brainpipe/executor.rb`
  - [ ] `initialize(callable, operation:, debug: false)`
  - [ ] `call(namespaces)` - array in, array out
  - [ ] `validate_reads!(namespace)` - check declared reads exist
  - [ ] `validate_sets!(before, after)` - check declared sets appear
  - [ ] `validate_deletes!(before, after)` - check declared deletes removed
  - [ ] Optional property handling (skip validation if optional)
  - [ ] Error handler invocation
  - [ ] Output count validation (same as input)
- [ ] Write specs for `Executor`
  - [ ] Read validation (present, missing, optional)
  - [ ] Set validation (present, missing, optional)
  - [ ] Delete validation (removed, still present, optional)
  - [ ] Error handler: boolean `true` (ignore all)
  - [ ] Error handler: proc (conditional ignore)
  - [ ] Output count mismatch error
  - [ ] Contract violation error messages

---

## Phase 5: Model Configuration

- [ ] Create `lib/brainpipe/capabilities.rb`
  - [ ] Capability constants: `TEXT_TO_TEXT`, `TEXT_TO_IMAGE`, `IMAGE_TO_TEXT`, `TEXT_IMAGE_TO_TEXT`, `TEXT_TO_AUDIO`, `AUDIO_TO_TEXT`, `TEXT_TO_EMBEDDING`
  - [ ] `VALID_CAPABILITIES` set
  - [ ] `valid_capability?(cap)` helper
- [ ] Create `lib/brainpipe/model_config.rb`
  - [ ] `initialize(name:, provider:, model:, capabilities:, options: {})`
  - [ ] `has_capability?(capability)`
  - [ ] `to_baml_client_registry` (stub for now, implement in Phase 13)
  - [ ] Immutable (freeze after init)
- [ ] Create `lib/brainpipe/model_registry.rb`
  - [ ] `register(name, config)`
  - [ ] `get(name)` - raises `MissingModelError` if not found
  - [ ] `get?(name)` - returns nil if not found
  - [ ] `clear!` - for testing
- [ ] Create `lib/brainpipe/secret_resolver.rb`
  - [ ] `resolve(value)` - handles `${ENV_VAR}` and `secret://ref`
  - [ ] Environment variable expansion
  - [ ] Secret reference detection (resolution delegated to configured resolver)
- [ ] Write specs for capabilities, model config, registry, secret resolver

---

## Phase 6: Stage Execution

- [ ] Add `concurrent-ruby` to gemspec
- [ ] Create `lib/brainpipe/stage.rb`
  - [ ] `MODES = [:merge, :fan_out, :batch]`
  - [ ] `MERGE_STRATEGIES = [:last_in, :first_in, :collate, :disjoint]`
  - [ ] `initialize(name:, mode:, operations:, merge_strategy: :last_in)`
  - [ ] `call(namespace_array)` - execute stage
  - [ ] `inputs` - aggregated from operations
  - [ ] `outputs` - aggregated from operations
  - [ ] `validate!` - for disjoint strategy
  - [ ] Mode implementations:
    - [ ] Merge mode: combine namespaces, run ops, return `[result]`
    - [ ] Fan-out mode: distribute namespaces, concurrent execution
    - [ ] Batch mode: pass entire array to operations
  - [ ] Parallel operation execution within stage
  - [ ] Merge strategy implementations:
    - [ ] `last_in`: last to complete wins
    - [ ] `first_in`: first to complete wins
    - [ ] `collate`: conflicts become arrays
    - [ ] `disjoint`: validate no overlap at config time
  - [ ] Empty input check (raise `EmptyInputError`)
- [ ] Write specs for `Stage`
  - [ ] Each mode
  - [ ] Each merge strategy
  - [ ] Parallel execution
  - [ ] Empty input error
  - [ ] Input/output aggregation

---

## Phase 7: Pipe Assembly & Validation

- [ ] Create `lib/brainpipe/pipe.rb`
  - [ ] `initialize(name:, stages:, timeout: nil)`
  - [ ] `call(properties)` - execute pipeline
  - [ ] `inputs` - from first stage
  - [ ] `outputs` - from last stage
  - [ ] `validate!` - stage compatibility
  - [ ] Validate last stage is merge mode
  - [ ] Validate stage property compatibility (outputs feed inputs)
- [ ] Write specs for `Pipe`
  - [ ] Construction validation
  - [ ] Input/output advertising
  - [ ] Last stage mode validation
  - [ ] Stage compatibility validation
  - [ ] Execution flow

---

## Phase 8: Configuration DSL

- [ ] Create `lib/brainpipe/configuration.rb`
  - [ ] `attr_accessor :config_path, :debug, :metrics_collector, :secret_resolver, :max_threads, :thread_pool_timeout`
  - [ ] `model(name, &block)` - define model config
  - [ ] `autoload_path(path)` - add Zeitwerk path
  - [ ] `register_operation(name, klass)` - explicit registration
  - [ ] `load_config!` - trigger YAML loading
  - [ ] Model builder DSL (provider, model, capabilities, options, api_key)
- [ ] Update `Brainpipe.configure` to use Configuration
- [ ] Write specs for Configuration DSL
  - [ ] Model definition
  - [ ] Operation registration
  - [ ] Autoload paths
  - [ ] Secret resolver
  - [ ] Thread pool settings
  - [ ] `load_config!` timing

---

## Phase 9: YAML Loading & Autoloading

- [ ] Add `zeitwerk` to gemspec
- [ ] Create `lib/brainpipe/loader.rb`
  - [ ] `load_config_file(path)` - parse config.yml
  - [ ] `load_pipe_file(path)` - parse pipe YAML
  - [ ] `setup_zeitwerk(paths)` - configure autoloader
  - [ ] `resolve_operation(type_string)` - find operation class
  - [ ] `build_pipe(yaml_hash)` - construct Pipe from YAML
  - [ ] `build_stage(yaml_hash)` - construct Stage from YAML
  - [ ] Capability validation (operation requires model with capability)
  - [ ] Secret resolution integration
- [ ] Update `Brainpipe.load!` to use Loader
- [ ] Create default Zeitwerk paths:
  - [ ] `app/operations/` (Rails)
  - [ ] `lib/operations/`
- [ ] Write specs for Loader
  - [ ] Valid config.yml parsing
  - [ ] Invalid YAML error handling
  - [ ] Pipe YAML parsing
  - [ ] Operation resolution (built-in, user-defined, registered)
  - [ ] Model reference resolution
  - [ ] Capability mismatch errors
  - [ ] Missing operation errors
  - [ ] Missing model errors

---

## Phase 10: Timeout & Error Handling

- [ ] Add timeout support to `Pipe`
  - [ ] Wrap `call` with `Timeout.timeout`
  - [ ] Raise `TimeoutError`
- [ ] Add timeout support to `Stage`
  - [ ] Wrap execution with timeout
  - [ ] Cancel in-flight operations on timeout
- [ ] Add timeout support to `Executor`
  - [ ] Per-operation timeout
- [ ] Implement parallel error collection in `Stage`
  - [ ] Let all operations complete
  - [ ] Collect success and failure results
  - [ ] Raise first non-ignored error after completion
- [ ] Update YAML loading to parse `timeout` field
- [ ] Write specs for timeout behavior
  - [ ] Pipe timeout
  - [ ] Stage timeout
  - [ ] Operation timeout
  - [ ] Timeout clamping (inner by outer)
- [ ] Write specs for parallel error handling
  - [ ] All ops complete before error raised
  - [ ] Ignored errors don't halt
  - [ ] Error collection for debugging

---

## Phase 11: Observability

- [ ] Create `lib/brainpipe/observability/debug.rb`
  - [ ] Debug output formatter
  - [ ] Operation start/end logging
  - [ ] Namespace state logging
- [ ] Create `lib/brainpipe/observability/metrics_collector.rb`
  - [ ] Interface definition
  - [ ] `operation_started(operation_class:, namespace:, stage:, pipe:)`
  - [ ] `operation_completed(operation_class:, namespace:, duration_ms:, stage:, pipe:)`
  - [ ] `operation_failed(operation_class:, namespace:, error:, duration_ms:, stage:, pipe:)`
  - [ ] `model_called(model_config:, input:, output:, tokens_in:, tokens_out:, duration_ms:)`
  - [ ] `pipe_completed(pipe:, input:, output:, duration_ms:, operations_count:)`
  - [ ] Null implementation (no-op for unimplemented methods)
- [ ] Integrate metrics collector into Executor, Stage, Pipe
- [ ] Write specs for observability
  - [ ] Debug output formatting
  - [ ] Metrics callback invocation
  - [ ] Null collector behavior

---

## Phase 12: Built-in Operations

- [ ] Create `lib/brainpipe/operations/` directory
- [ ] Create `lib/brainpipe/operations/transform.rb`
  - [ ] Property mapping/transformation
  - [ ] Configurable via options
- [ ] Create `lib/brainpipe/operations/filter.rb`
  - [ ] Conditional pass-through
  - [ ] Configurable condition
- [ ] Create `lib/brainpipe/operations/merge.rb`
  - [ ] Combine properties from namespace
- [ ] Create `lib/brainpipe/operations/log.rb`
  - [ ] Debug logging of namespace state
- [ ] Write specs for each built-in operation
- [ ] Integration tests with built-ins in pipes

---

## Phase 13: BAML Integration

- [ ] Add `baml` as optional dependency in gemspec
- [ ] Create `lib/brainpipe/baml_adapter.rb`
  - [ ] `function(name)` - get BAML function
  - [ ] `input_schema(function)` - extract input types
  - [ ] `output_schema(function)` - extract output types
  - [ ] Check if BAML is available
- [ ] Create `lib/brainpipe/operations/baml.rb`
  - [ ] `function(name)` DSL
  - [ ] Dynamic `declared_reads` from BAML schema
  - [ ] Dynamic `declared_sets` from BAML schema
  - [ ] Execution via BAML client
  - [ ] Metrics integration (token tracking)
- [ ] Implement `ModelConfig#to_baml_client_registry`
- [ ] Write specs for BAML integration
  - [ ] Function wrapping
  - [ ] Schema introspection
  - [ ] Client registry conversion
  - [ ] Graceful degradation when BAML not installed
- [ ] Integration test with BAML operation in pipe

---

## Final Tasks

- [ ] Review all public API for consistency
- [ ] Ensure all errors have useful messages
- [ ] Add YARD documentation to public methods
- [ ] Update README with usage examples
- [ ] Create CHANGELOG.md
- [ ] Verify gemspec metadata
- [ ] Test gem installation from local build
