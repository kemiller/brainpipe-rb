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

- [x] Create `lib/brainpipe/executor.rb`
  - [x] `initialize(callable, operation:, debug: false)`
  - [x] `call(namespaces)` - array in, array out
  - [x] `validate_reads!(namespace)` - check declared reads exist
  - [x] `validate_sets!(before, after)` - check declared sets appear
  - [x] `validate_deletes!(before, after)` - check declared deletes removed
  - [x] Optional property handling (skip validation if optional)
  - [x] Error handler invocation
  - [x] Output count validation (same as input)
- [x] Write specs for `Executor`
  - [x] Read validation (present, missing, optional)
  - [x] Set validation (present, missing, optional)
  - [x] Delete validation (removed, still present, optional)
  - [x] Error handler: boolean `true` (ignore all)
  - [x] Error handler: proc (conditional ignore)
  - [x] Output count mismatch error
  - [x] Contract violation error messages

---

## Phase 5: Model Configuration

- [x] Create `lib/brainpipe/capabilities.rb`
  - [x] Capability constants: `TEXT_TO_TEXT`, `TEXT_TO_IMAGE`, `IMAGE_TO_TEXT`, `TEXT_IMAGE_TO_TEXT`, `TEXT_TO_AUDIO`, `AUDIO_TO_TEXT`, `TEXT_TO_EMBEDDING`
  - [x] `VALID_CAPABILITIES` set
  - [x] `valid?(cap)` helper
- [x] Create `lib/brainpipe/model_config.rb`
  - [x] `initialize(name:, provider:, model:, capabilities:, options: {})`
  - [x] `has_capability?(capability)`
  - [x] `to_baml_client_registry` (stub for now, implement in Phase 13)
  - [x] Immutable (freeze after init)
- [x] Create `lib/brainpipe/model_registry.rb`
  - [x] `register(name, config)`
  - [x] `get(name)` - raises `MissingModelError` if not found
  - [x] `get?(name)` - returns nil if not found
  - [x] `clear!` - for testing
- [x] Create `lib/brainpipe/secret_resolver.rb`
  - [x] `resolve(value)` - handles `${ENV_VAR}` and `secret://ref`
  - [x] Environment variable expansion
  - [x] Secret reference detection (resolution delegated to configured resolver)
- [x] Write specs for capabilities, model config, registry, secret resolver

---

## Phase 6: Stage Execution

- [x] Add `concurrent-ruby` to gemspec
- [x] Create `lib/brainpipe/stage.rb`
  - [x] `MODES = [:merge, :fan_out, :batch]`
  - [x] `MERGE_STRATEGIES = [:last_in, :first_in, :collate, :disjoint]`
  - [x] `initialize(name:, mode:, operations:, merge_strategy: :last_in)`
  - [x] `call(namespace_array)` - execute stage
  - [x] `inputs` - aggregated from operations
  - [x] `outputs` - aggregated from operations
  - [x] `validate!` - for disjoint strategy
  - [x] Mode implementations:
    - [x] Merge mode: combine namespaces, run ops, return `[result]`
    - [x] Fan-out mode: distribute namespaces, concurrent execution
    - [x] Batch mode: pass entire array to operations
  - [x] Parallel operation execution within stage
  - [x] Merge strategy implementations:
    - [x] `last_in`: last to complete wins
    - [x] `first_in`: first to complete wins
    - [x] `collate`: conflicts become arrays
    - [x] `disjoint`: validate no overlap at config time
  - [x] Empty input check (raise `EmptyInputError`)
- [x] Write specs for `Stage`
  - [x] Each mode
  - [x] Each merge strategy
  - [x] Parallel execution
  - [x] Empty input error
  - [x] Input/output aggregation

---

## Phase 7: Pipe Assembly & Validation

- [x] Create `lib/brainpipe/pipe.rb`
  - [x] `initialize(name:, stages:, timeout: nil)`
  - [x] `call(properties)` - execute pipeline
  - [x] `inputs` - from first stage
  - [x] `outputs` - from last stage
  - [x] `validate!` - stage compatibility
  - [x] Validate last stage is merge mode
  - [x] Validate stage property compatibility (outputs feed inputs)
- [x] Write specs for `Pipe`
  - [x] Construction validation
  - [x] Input/output advertising
  - [x] Last stage mode validation
  - [x] Stage compatibility validation
  - [x] Execution flow

---

## Phase 8: Configuration DSL

- [x] Create `lib/brainpipe/configuration.rb`
  - [x] `attr_accessor :config_path, :debug, :metrics_collector, :secret_resolver, :max_threads, :thread_pool_timeout`
  - [x] `model(name, &block)` - define model config
  - [x] `autoload_path(path)` - add Zeitwerk path
  - [x] `register_operation(name, klass)` - explicit registration
  - [x] `load_config!` - trigger YAML loading
  - [x] Model builder DSL (provider, model, capabilities, options, api_key)
- [x] Update `Brainpipe.configure` to use Configuration
- [x] Write specs for Configuration DSL
  - [x] Model definition
  - [x] Operation registration
  - [x] Autoload paths
  - [x] Secret resolver
  - [x] Thread pool settings
  - [x] `load_config!` timing

---

## Phase 9: YAML Loading & Autoloading

- [x] Add `zeitwerk` to gemspec
- [x] Create `lib/brainpipe/loader.rb`
  - [x] `load_config_file(path)` - parse config.yml
  - [x] `load_pipe_file(path)` - parse pipe YAML
  - [x] `setup_zeitwerk(paths)` - configure autoloader
  - [x] `resolve_operation(type_string)` - find operation class
  - [x] `build_pipe(yaml_hash)` - construct Pipe from YAML
  - [x] `build_stage(yaml_hash)` - construct Stage from YAML
  - [x] Capability validation (operation requires model with capability)
  - [x] Secret resolution integration
- [x] Update `Brainpipe.load!` to use Loader
- [x] Create default Zeitwerk paths:
  - [x] `app/operations/` (Rails)
  - [x] `lib/operations/`
- [x] Write specs for Loader
  - [x] Valid config.yml parsing
  - [x] Invalid YAML error handling
  - [x] Pipe YAML parsing
  - [x] Operation resolution (built-in, user-defined, registered)
  - [x] Model reference resolution
  - [x] Capability mismatch errors
  - [x] Missing operation errors
  - [x] Missing model errors

---

## Phase 10: Timeout & Error Handling

- [x] Add timeout support to `Pipe`
  - [x] Wrap `call` with `Timeout.timeout`
  - [x] Raise `TimeoutError`
- [x] Add timeout support to `Stage`
  - [x] Wrap execution with timeout
  - [x] Cancel in-flight operations on timeout
- [x] Add timeout support to `Executor`
  - [x] Per-operation timeout
- [x] Implement parallel error collection in `Stage`
  - [x] Let all operations complete
  - [x] Collect success and failure results
  - [x] Raise first non-ignored error after completion
- [x] Update YAML loading to parse `timeout` field
- [x] Write specs for timeout behavior
  - [x] Pipe timeout
  - [x] Stage timeout
  - [x] Operation timeout
  - [x] Timeout clamping (inner by outer)
- [x] Write specs for parallel error handling
  - [x] All ops complete before error raised
  - [x] Ignored errors don't halt
  - [x] Error collection for debugging

---

## Phase 11: Observability

- [x] Create `lib/brainpipe/observability/debug.rb`
  - [x] Debug output formatter
  - [x] Operation start/end logging
  - [x] Namespace state logging
- [x] Create `lib/brainpipe/observability/metrics_collector.rb`
  - [x] Interface definition
  - [x] `operation_started(operation_class:, namespace:, stage:, pipe:)`
  - [x] `operation_completed(operation_class:, namespace:, duration_ms:, stage:, pipe:)`
  - [x] `operation_failed(operation_class:, namespace:, error:, duration_ms:, stage:, pipe:)`
  - [x] `model_called(model_config:, input:, output:, tokens_in:, tokens_out:, duration_ms:)`
  - [x] `pipe_completed(pipe:, input:, output:, duration_ms:, operations_count:)`
  - [x] Null implementation (no-op for unimplemented methods)
- [x] Integrate metrics collector into Executor, Stage, Pipe
- [x] Write specs for observability
  - [x] Debug output formatting
  - [x] Metrics callback invocation
  - [x] Null collector behavior

---

## Phase 12: Built-in Operations (Type-Safe)

- [x] Update prerequisites for type flow support
  - [x] Update `lib/brainpipe/operation.rb` - `declared_reads/sets/deletes` accept `prefix_schema = {}`
  - [x] Update `lib/brainpipe/pipe.rb` - pass prefix schema during validation, add `validate_parallel_type_consistency!`
  - [x] Update `lib/brainpipe/stage.rb` - pass prefix schema to operations in aggregate methods
  - [x] Add `TypeConflictError` to `lib/brainpipe/errors.rb`
- [x] Create `lib/brainpipe/operations/` directory
- [x] Create `lib/brainpipe/operations/transform.rb`
  - [x] Rename/copy fields with type preservation via prefix_schema lookup
  - [x] Options: `from`, `to`, `delete_source`
- [x] Create `lib/brainpipe/operations/filter.rb`
  - [x] Conditional pass-through (pure passthrough for schema)
  - [x] Options: `field`/`value` or custom `condition` proc
- [x] Create `lib/brainpipe/operations/merge.rb`
  - [x] Combine multiple fields into one
  - [x] Options: `sources`, `target`, `combiner`, `target_type`, `delete_sources`
- [x] Create `lib/brainpipe/operations/log.rb`
  - [x] Debug logging (pure passthrough, no schema changes)
  - [x] Options: `fields`, `message`, `level`
- [x] Write specs for type preservation
  - [x] Transform renames field with correct type in output schema
  - [x] Chained transforms preserve type through chain
  - [x] Merge enforces explicit target_type
- [x] Write specs for type conflict detection
  - [x] Parallel ops setting same field with same type: OK
  - [x] Parallel ops setting same field with different types: `TypeConflictError`
- [x] Write specs for schema flow
  - [x] Verify `prefix - deletes + sets` calculation
  - [x] Fields not touched by operation flow through unchanged
- [x] Write specs for each built-in operation
  - [x] Transform: rename, copy, type lookup
  - [x] Filter: field/value match, custom condition, subset output
  - [x] Merge: multiple sources, target_type, optional deletion
  - [x] Log: pure passthrough
- [x] Integration tests with built-ins in pipes

---

## Phase 13: BAML Integration

- [x] Add `baml` as optional dependency in gemspec
- [x] Create `lib/brainpipe/baml_adapter.rb`
  - [x] `function(name)` - get BAML function
  - [x] `input_schema(function)` - extract input types
  - [x] `output_schema(function)` - extract output types
  - [x] Check if BAML is available
- [x] Create `lib/brainpipe/operations/baml.rb`
  - [x] `function(name)` DSL
  - [x] Dynamic `declared_reads` from BAML schema
  - [x] Dynamic `declared_sets` from BAML schema
  - [x] Execution via BAML client
  - [x] Metrics integration (token tracking)
- [x] Implement `ModelConfig#to_baml_client_registry`
- [x] Write specs for BAML integration
  - [x] Function wrapping
  - [x] Schema introspection
  - [x] Client registry conversion
  - [x] Graceful degradation when BAML not installed
- [x] Integration test with BAML operation in pipe

---

---

## Phase 14: Image Support

### Task 14.1: Create Image type
**File:** `lib/brainpipe/image.rb`

- [x] Implement `Brainpipe::Image` class
  - [x] `initialize(url: nil, base64: nil, mime_type: nil)`
  - [x] `self.from_url(url, mime_type: nil)`
  - [x] `self.from_base64(data, mime_type:)`
  - [x] `self.from_file(path)`
  - [x] `url?`, `base64?` predicates
  - [x] `url` accessor (raises if base64-only)
  - [x] `base64` accessor (lazy fetch from URL via Net::HTTP)
  - [x] `to_baml_image` conversion
  - [x] MIME type inference from file extensions
  - [x] Freeze after construction

### Task 14.2: Add Image require
**File:** `lib/brainpipe.rb`

- [x] Add `require_relative "brainpipe/image"`

### Task 14.3: Test Image type
**File:** `spec/brainpipe/image_spec.rb`

- [x] Test `.from_file` loads image and infers MIME type
- [x] Test `.from_url` stores URL without fetching
- [x] Test `.from_url` fetches base64 lazily
- [x] Test `.from_base64` stores data with MIME type
- [x] Test `#to_baml_image` converts to BAML Image type
- [x] Test instance is frozen after construction

**Run:** `bundle exec rspec spec/brainpipe/image_spec.rb`

---

## Phase 15: Image Extractors

### Task 15.1: Create extractors directory and GeminiImage extractor
**File:** `lib/brainpipe/extractors/gemini_image.rb`

- [x] Create `Brainpipe::Extractors` module
- [x] Implement `GeminiImage.call(response)` that extracts image from Gemini response format

### Task 15.2: Add extractor require
**File:** `lib/brainpipe.rb`

- [x] Add `require_relative "brainpipe/extractors/gemini_image"`

### Task 15.3: Test GeminiImage extractor
**File:** `spec/brainpipe/extractors/gemini_image_spec.rb`

- [x] Test extracts image from valid Gemini response with inlineData
- [x] Test returns nil when no image in response
- [x] Test handles empty response gracefully
- [x] Test handles response with text-only parts

**Run:** `bundle exec rspec spec/brainpipe/extractors/gemini_image_spec.rb`

---

## Phase 16: BamlRaw Operation

### Task 16.1: Add IMAGE_EDIT capability
**File:** `lib/brainpipe/capabilities.rb`

- [ ] Add `IMAGE_EDIT = :image_edit` if not present
- [ ] Add to `VALID_CAPABILITIES`

### Task 16.2: Create BamlRaw operation
**File:** `lib/brainpipe/operations/baml_raw.rb`

- [ ] Accept options: `function`, `inputs`, `image_extractor`, `output_field`
- [ ] Use BAML Modular API (`Baml::Client.request.FunctionName`) to build raw request
- [ ] Execute HTTP request via Net::HTTP
- [ ] Pass raw JSON response to extractor
- [ ] Merge extracted image into namespace under `output_field`
- [ ] Declare reads based on `inputs` mapping
- [ ] Declare sets based on `output_field`

### Task 16.3: Add BamlRaw require
**File:** `lib/brainpipe.rb`

- [ ] Add `require_relative "brainpipe/operations/baml_raw"`

### Task 16.4: Test BamlRaw operation
**File:** `spec/brainpipe/operations/baml_raw_spec.rb`

- [ ] Test `#create` returns a callable
- [ ] Test execution extracts image from mocked raw response
- [ ] Test input mapping from namespace
- [ ] Test output field configuration
- [ ] Test error handling for failed HTTP requests
- [ ] Test error handling when extractor returns nil

**Run:** `bundle exec rspec spec/brainpipe/operations/baml_raw_spec.rb`

---

## Phase 17: Image Fixer Example

### Task 17.1: Create example directory structure
```
examples/image_fixer/
├── baml_src/
├── config/
│   └── brainpipe/
│       └── pipes/
└── sample.jpg
```

### Task 17.2: Create BAML functions
**File:** `examples/image_fixer/baml_src/image_fixer.baml`

- [ ] Define `Problem` class
- [ ] Define `ImageAnalysis` class
- [ ] Define `AnalyzeImageProblems(img: image) -> ImageAnalysis`
- [ ] Define `FixImageProblems(img: image, instructions: string) -> string`
- [ ] Define client configurations for Gemini models

### Task 17.3: Create model config
**File:** `examples/image_fixer/config/brainpipe/config.yml`

- [ ] Configure `gemini` model (gemini-2.0-flash)
- [ ] Configure `gemini_flash_image` model (gemini-2.5-flash-preview-04-17)

### Task 17.4: Create pipeline config
**File:** `examples/image_fixer/config/brainpipe/pipes/image_fixer.yml`

- [ ] Define `analyze` stage with Baml operation
- [ ] Define `fix` stage with BamlRaw operation

### Task 17.5: Create demo script
**File:** `examples/image_fixer/run.rb`

- [ ] Load Brainpipe configuration
- [ ] Load input image from argument or default
- [ ] Run pipeline
- [ ] Print analysis results
- [ ] Save fixed image to file

### Task 17.6: Test example end-to-end
**Manual test:**
```bash
cd examples/image_fixer
export GOOGLE_AI_API_KEY=your-key
ruby run.rb sample.jpg
```

- [ ] Verify analysis prints to console
- [ ] Verify `fixed_sample.png` is created

---

## Phase Summary

| Phase | Description | Test Command                                                       |
|-------|-------------|--------------------------------------------------------------------|
| 14    | Image Type  | `bundle exec rspec spec/brainpipe/image_spec.rb`                   |
| 15    | Extractors  | `bundle exec rspec spec/brainpipe/extractors/gemini_image_spec.rb` |
| 16    | BamlRaw     | `bundle exec rspec spec/brainpipe/operations/baml_raw_spec.rb`     |
| 17    | Example     | Manual: `ruby examples/image_fixer/run.rb`                         |

**Full test suite:** `bundle exec rspec`

---

## Final Tasks

- [ ] Review all public API for consistency
- [ ] Ensure all errors have useful messages
- [ ] Add YARD documentation to public methods
- [ ] Update README with usage examples
- [ ] Update CHANGELOG.md
- [x] Verify gemspec metadata
- [x] Test gem installation from local build
