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

- [x] Add `IMAGE_EDIT = :image_edit` if not present
- [x] Add to `VALID_CAPABILITIES`

### Task 16.2: Create BamlRaw operation
**File:** `lib/brainpipe/operations/baml_raw.rb`

- [x] Accept options: `function`, `inputs`, `image_extractor`, `output_field`
- [x] Use BAML Modular API (`Baml::Client.request.FunctionName`) to build raw request
- [x] Execute HTTP request via Net::HTTP
- [x] Pass raw JSON response to extractor
- [x] Merge extracted image into namespace under `output_field`
- [x] Declare reads based on `inputs` mapping
- [x] Declare sets based on `output_field`

### Task 16.3: Add BamlRaw require
**File:** `lib/brainpipe.rb`

- [x] Add `require_relative "brainpipe/operations/baml_raw"`

### Task 16.4: Test BamlRaw operation
**File:** `spec/brainpipe/operations/baml_raw_spec.rb`

- [x] Test `#create` returns a callable
- [x] Test execution extracts image from mocked raw response
- [x] Test input mapping from namespace
- [x] Test output field configuration
- [x] Test error handling for failed HTTP requests
- [x] Test error handling when extractor returns nil

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

- [x] Directory structure created

### Task 17.2: Create BAML functions
**File:** `examples/image_fixer/baml_src/main.baml`

- [x] Define `Problem` class
- [x] Define `ImageAnalysis` class
- [x] Define `AnalyzeImageProblems(img: image) -> ImageAnalysis`
- [x] Define `FixImageProblems(img: image, instructions: string) -> string`
- [x] Define client configurations for Gemini models

### Task 17.3: Create model config
**File:** `examples/image_fixer/config/brainpipe/config.yml`

- [x] Configure `gemini` model (gemini-2.0-flash)
- [x] Configure `gemini_flash_image` model (gemini-2.0-flash-exp with generation_config)

### Task 17.4: Create pipeline config
**File:** `examples/image_fixer/config/brainpipe/pipes/image_fixer.yml`

- [x] Define `analyze` stage with Baml operation
- [x] Define `fix` stage with BamlRaw operation

### Task 17.5: Create demo script
**File:** `examples/image_fixer/run.rb`

- [x] Load Brainpipe configuration
- [x] Load input image from argument or default
- [x] Run pipeline
- [x] Print analysis results
- [x] Save fixed image to file

### Task 17.6: Test example end-to-end
**Manual test:**
```bash
cd examples/image_fixer
export GOOGLE_AI_API_KEY=your-key
bundle exec ruby run.rb
```

- [x] Verify analysis prints to console
- [x] Verify `fixed_sample.png` is created

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

## Phase 18: Provider Adapters

### Task 18.1: Create provider adapters infrastructure
**File:** `lib/brainpipe/provider_adapters.rb`

- [ ] Create `Brainpipe::ProviderAdapters` module
- [ ] Implement `register(provider, adapter_class)` for adapter registration
- [ ] Implement `for(provider)` to retrieve adapter by provider name
- [ ] Implement `normalize_provider(provider)` - converts "google-ai" to `:google_ai`
- [ ] Implement `to_baml_provider(provider)` - converts `:google_ai` to `"google-ai"`
- [ ] Raise `ConfigurationError` for unknown providers

### Task 18.2: Create base adapter class
**File:** `lib/brainpipe/provider_adapters/base.rb`

- [ ] `call(prompt:, model_config:, images: [], json_mode: false)` - abstract, raises NotImplementedError
- [ ] `extract_text(response)` - abstract, raises NotImplementedError
- [ ] `extract_image(response)` - default returns nil (override where supported)
- [ ] `build_headers(model_config)` - helper for auth headers
- [ ] `execute_request(uri, body, headers)` - shared HTTP execution via Net::HTTP

### Task 18.3: Create OpenAI adapter
**File:** `lib/brainpipe/provider_adapters/openai.rb`

- [ ] Implement `call` for chat completions API
  - [ ] Build messages array with user content
  - [ ] Handle images as base64 data URLs in content array
  - [ ] Set `response_format: { type: "json_object" }` when json_mode
- [ ] Implement `extract_text` - `response.dig("choices", 0, "message", "content")`
- [ ] Note: No image generation in chat completions (DALL-E uses different API)

### Task 18.4: Create Anthropic adapter
**File:** `lib/brainpipe/provider_adapters/anthropic.rb`

- [ ] Implement `call` for messages API
  - [ ] Build content array with text and image blocks
  - [ ] Handle images as base64 with media_type
  - [ ] Set appropriate headers (anthropic-version, x-api-key)
- [ ] Implement `extract_text` - `response.dig("content", 0, "text")`
- [ ] Note: No image generation currently supported

### Task 18.5: Create Google AI adapter
**File:** `lib/brainpipe/provider_adapters/google_ai.rb`

- [ ] Implement `call` for generateContent API
  - [ ] Build parts array with text and inlineData
  - [ ] Handle images as base64 inlineData with mimeType
  - [ ] Support generationConfig for temperature, etc.
- [ ] Implement `extract_text` - `response.dig("candidates", 0, "content", "parts", 0, "text")`
- [ ] Implement `extract_image` - find part with inlineData, return `Image.from_base64`

### Task 18.6: Register adapters
**File:** `lib/brainpipe/provider_adapters.rb`

- [ ] Register `:openai` adapter
- [ ] Register `:anthropic` adapter
- [ ] Register `:google_ai` adapter

### Task 18.7: Add requires
**File:** `lib/brainpipe.rb`

- [ ] Add `require_relative "brainpipe/provider_adapters"`
- [ ] Add `require_relative "brainpipe/provider_adapters/base"`
- [ ] Add `require_relative "brainpipe/provider_adapters/openai"`
- [ ] Add `require_relative "brainpipe/provider_adapters/anthropic"`
- [ ] Add `require_relative "brainpipe/provider_adapters/google_ai"`

### Task 18.8: Test provider adapters
**File:** `spec/brainpipe/provider_adapters_spec.rb`

- [ ] Test `normalize_provider` converts hyphens to underscores
- [ ] Test `to_baml_provider` converts underscores to hyphens
- [ ] Test `for` returns correct adapter for each provider
- [ ] Test `for` raises ConfigurationError for unknown provider

**File:** `spec/brainpipe/provider_adapters/openai_spec.rb`

- [ ] Test request building with text-only prompt
- [ ] Test request building with images
- [ ] Test json_mode sets response_format
- [ ] Test extract_text from response

**File:** `spec/brainpipe/provider_adapters/anthropic_spec.rb`

- [ ] Test request building with text-only prompt
- [ ] Test request building with images
- [ ] Test extract_text from response

**File:** `spec/brainpipe/provider_adapters/google_ai_spec.rb`

- [ ] Test request building with text-only prompt
- [ ] Test request building with images
- [ ] Test extract_text from response
- [ ] Test extract_image from response with inlineData

**Run:** `bundle exec rspec spec/brainpipe/provider_adapters*`

---

## Phase 19: LlmCall Operation

### Task 19.1: Add mustache dependency
**File:** `brainpipe.gemspec`

- [ ] Add `spec.add_dependency "mustache", "~> 1.0"`

### Task 19.2: Create LlmCall operation
**File:** `lib/brainpipe/operations/llm_call.rb`

- [ ] `initialize(model: nil, options: {})`
  - [ ] Load template from `prompt` or `prompt_file`
  - [ ] Store `capability`, `inputs`, `outputs`
  - [ ] Resolve optional `image_extractor` override
  - [ ] Set `json_mode` default based on output types
- [ ] `required_model_capability` - returns `@capability`
- [ ] `declared_reads(prefix_schema = {})` - returns `@input_types`
- [ ] `declared_sets(prefix_schema = {})` - returns `@output_types`
- [ ] `create` - returns callable that:
  - [ ] Gets adapter via `ProviderAdapters.for(model_config.provider)`
  - [ ] Builds context from namespace (images marked as placeholders)
  - [ ] Extracts images from namespace
  - [ ] Renders template with `Mustache.render(template, context)`
  - [ ] Calls `adapter.call(prompt:, model_config:, images:, json_mode:)`
  - [ ] For image outputs: uses override extractor or `adapter.extract_image`
  - [ ] For text outputs: parses JSON, validates, merges into namespace

### Task 19.3: Add template loading
**File:** `lib/brainpipe/operations/llm_call.rb`

- [ ] `load_template(options)` private method
  - [ ] If `prompt` key, return string directly
  - [ ] If `prompt_file` key, read file relative to config path
  - [ ] Raise ConfigurationError if neither present

### Task 19.4: Add LlmCall require
**File:** `lib/brainpipe.rb`

- [ ] Add `require "mustache"` (guarded or in operation file)
- [ ] Add `require_relative "brainpipe/operations/llm_call"`

### Task 19.5: Update loader for LlmCall
**File:** `lib/brainpipe/loader.rb`

- [ ] Ensure `Brainpipe::Operations::LlmCall` is resolvable
- [ ] Validate `capability` is present and valid
- [ ] Validate model has required capability

### Task 19.6: Test LlmCall operation
**File:** `spec/brainpipe/operations/llm_call_spec.rb`

- [ ] Test `required_model_capability` returns configured capability
- [ ] Test `declared_reads` returns input types
- [ ] Test `declared_sets` returns output types
- [ ] Test template loading from inline `prompt`
- [ ] Test template loading from `prompt_file`
- [ ] Test Mustache interpolation of variables
- [ ] Test Mustache section iteration for arrays
- [ ] Test image input handling (placeholder in context, extracted separately)
- [ ] Test text output parsing and validation
- [ ] Test image output extraction via adapter
- [ ] Test image output extraction via override extractor
- [ ] Test json_mode default behavior

**Run:** `bundle exec rspec spec/brainpipe/operations/llm_call_spec.rb`

---

## Phase 20: Entity Extractor Example

### Task 20.1: Create example directory structure
```
examples/entity_extractor/
├── config/
│   └── brainpipe/
│       └── pipes/
├── prompts/
└── run.rb
```

- [ ] Directory structure created

### Task 20.2: Create model config
**File:** `examples/entity_extractor/config/brainpipe/config.yml`

- [ ] Configure `openai` model
- [ ] Configure `anthropic` model
- [ ] Configure `gemini` model

### Task 20.3: Create pipeline config
**File:** `examples/entity_extractor/config/brainpipe/pipes/entity_extractor.yml`

- [ ] Define `extract` stage with LlmCall operation
- [ ] Set capability: `text_to_text`
- [ ] Reference prompt template file

### Task 20.4: Create prompt template
**File:** `examples/entity_extractor/prompts/extract_entities.mustache`

- [ ] Mustache template with `{{{ input_text }}}` interpolation
- [ ] Section for entity_types iteration
- [ ] JSON output instructions

### Task 20.5: Create demo script
**File:** `examples/entity_extractor/run.rb`

- [ ] Load Brainpipe configuration
- [ ] Run pipeline with sample text
- [ ] Print extracted entities

### Task 20.6: Test example end-to-end
**Manual test:**
```bash
cd examples/entity_extractor
export OPENAI_API_KEY=your-key
bundle exec ruby run.rb
```

- [ ] Verify entities printed to console
- [ ] Test switching to different provider (anthropic, gemini)

---

## Phase Summary (18-20)

| Phase | Description | Test Command |
|-------|-------------|--------------|
| 18 | Provider Adapters | `bundle exec rspec spec/brainpipe/provider_adapters*` |
| 19 | LlmCall Operation | `bundle exec rspec spec/brainpipe/operations/llm_call_spec.rb` |
| 20 | Entity Example | Manual: `ruby examples/entity_extractor/run.rb` |

**Full test suite:** `bundle exec rspec`

---

## Implementation Notes

### Provider Adapter Design

The adapter pattern isolates all provider-specific logic:
- Request format (messages structure, image encoding)
- Authentication (header names, key format)
- Response parsing (different JSON structures)
- Image extraction (where supported)

Each adapter is stateless and receives all context via method parameters.

### Mustache Template Considerations

- Use `{{{ }}}` (triple mustache) for unescaped content to avoid HTML escaping
- Images in templates are rendered as `[IMAGE]` placeholder; actual image data passed separately to adapter
- Template files use `.mustache` extension by convention
- Mustache sections (`{{# list }}`) work with arrays for iteration

### Provider Symbol Normalization

BAML uses hyphenated provider names (`"google-ai"`), Ruby idiom is underscored symbols (`:google_ai`).
The adapter registry normalizes on input:
```ruby
ProviderAdapters.for("google-ai")  # works
ProviderAdapters.for(:google_ai)   # works
ProviderAdapters.for("google_ai")  # works
```

### Image Handling in LlmCall

1. Images in namespace are detected during context building
2. Context gets `[IMAGE]` placeholder for template rendering
3. Actual images extracted separately and passed to adapter
4. Adapter encodes images appropriately for provider (base64 data URL, inlineData, etc.)

### JSON Mode

- Defaults to `true` for text outputs, `false` for image outputs
- OpenAI: sets `response_format: { type: "json_object" }`
- Anthropic: no native JSON mode (relies on prompt)
- Google AI: no native JSON mode (relies on prompt)

---

## Final Tasks

- [ ] Review all public API for consistency
- [ ] Ensure all errors have useful messages
- [ ] Add YARD documentation to public methods
- [ ] Update README with usage examples
- [ ] Update CHANGELOG.md
- [x] Verify gemspec metadata
- [x] Test gem installation from local build
