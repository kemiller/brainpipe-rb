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
| 15    | Extractors  | *(Superseded by Phase 18 - consolidated into Provider Adapters)*   |
| 16    | BamlRaw     | `bundle exec rspec spec/brainpipe/operations/baml_raw_spec.rb`     |
| 17    | Example     | Manual: `ruby examples/image_fixer/run.rb`                         |

**Full test suite:** `bundle exec rspec`

> **Note:** Phase 15 (Image Extractors) was superseded by Phase 18 (Provider Adapters).
> Image extraction logic is now consolidated into provider adapters via `adapter.extract_image(response)`.
> The separate `Extractors` module and `image_extractor` option have been removed.

---

## Phase 18: Provider Adapters

### Task 18.1: Create provider adapters infrastructure
**File:** `lib/brainpipe/provider_adapters.rb`

- [x] Create `Brainpipe::ProviderAdapters` module
- [x] Implement `register(provider, adapter_class)` for adapter registration
- [x] Implement `for(provider)` to retrieve adapter by provider name
- [x] Implement `normalize_provider(provider)` - converts "google-ai" to `:google_ai`
- [x] Implement `to_baml_provider(provider)` - converts `:google_ai` to `"google-ai"`
- [x] Raise `ConfigurationError` for unknown providers

### Task 18.2: Create base adapter class
**File:** `lib/brainpipe/provider_adapters/base.rb`

- [x] `call(prompt:, model_config:, images: [], json_mode: false)` - abstract, raises NotImplementedError
- [x] `extract_text(response)` - abstract, raises NotImplementedError
- [x] `extract_image(response)` - default returns nil (override where supported)
- [x] `build_headers(model_config)` - helper for auth headers
- [x] `execute_request(uri, body, headers)` - shared HTTP execution via Net::HTTP

### Task 18.3: Create OpenAI adapter
**File:** `lib/brainpipe/provider_adapters/openai.rb`

- [x] Implement `call` for chat completions API
  - [x] Build messages array with user content
  - [x] Handle images as base64 data URLs in content array
  - [x] Set `response_format: { type: "json_object" }` when json_mode
- [x] Implement `extract_text` - `response.dig("choices", 0, "message", "content")`
- [x] Note: No image generation in chat completions (DALL-E uses different API)

### Task 18.4: Create Anthropic adapter
**File:** `lib/brainpipe/provider_adapters/anthropic.rb`

- [x] Implement `call` for messages API
  - [x] Build content array with text and image blocks
  - [x] Handle images as base64 with media_type
  - [x] Set appropriate headers (anthropic-version, x-api-key)
- [x] Implement `extract_text` - `response.dig("content", 0, "text")`
- [x] Note: No image generation currently supported

### Task 18.5: Create Google AI adapter
**File:** `lib/brainpipe/provider_adapters/google_ai.rb`

- [x] Implement `call` for generateContent API
  - [x] Build parts array with text and inlineData
  - [x] Handle images as base64 inlineData with mimeType
  - [x] Support generationConfig for temperature, etc.
- [x] Implement `extract_text` - `response.dig("candidates", 0, "content", "parts", 0, "text")`
- [x] Implement `extract_image` - find part with inlineData, return `Image.from_base64`

### Task 18.6: Register adapters
**File:** `lib/brainpipe/provider_adapters.rb`

- [x] Register `:openai` adapter
- [x] Register `:anthropic` adapter
- [x] Register `:google_ai` adapter

### Task 18.7: Add requires
**File:** `lib/brainpipe.rb`

- [x] Add `require_relative "brainpipe/provider_adapters"`
- [x] Add `require_relative "brainpipe/provider_adapters/base"`
- [x] Add `require_relative "brainpipe/provider_adapters/openai"`
- [x] Add `require_relative "brainpipe/provider_adapters/anthropic"`
- [x] Add `require_relative "brainpipe/provider_adapters/google_ai"`

### Task 18.8: Test provider adapters
**File:** `spec/brainpipe/provider_adapters_spec.rb`

- [x] Test `normalize_provider` converts hyphens to underscores
- [x] Test `to_baml_provider` converts underscores to hyphens
- [x] Test `for` returns correct adapter for each provider
- [x] Test `for` raises ConfigurationError for unknown provider

**File:** `spec/brainpipe/provider_adapters/openai_spec.rb`

- [x] Test request building with text-only prompt
- [x] Test request building with images
- [x] Test json_mode sets response_format
- [x] Test extract_text from response

**File:** `spec/brainpipe/provider_adapters/anthropic_spec.rb`

- [x] Test request building with text-only prompt
- [x] Test request building with images
- [x] Test extract_text from response

**File:** `spec/brainpipe/provider_adapters/google_ai_spec.rb`

- [x] Test request building with text-only prompt
- [x] Test request building with images
- [x] Test extract_text from response
- [x] Test extract_image from response with inlineData

**Run:** `bundle exec rspec spec/brainpipe/provider_adapters*`

---

## Phase 19: LlmCall Operation

### Task 19.1: Add mustache dependency
**File:** `brainpipe.gemspec`

- [x] Add `spec.add_dependency "mustache", "~> 1.0"`

### Task 19.2: Create LlmCall operation
**File:** `lib/brainpipe/operations/llm_call.rb`

- [x] `initialize(model: nil, options: {})`
  - [x] Load template from `prompt` or `prompt_file`
  - [x] Store `capability`, `inputs`, `outputs`
  - [x] Set `json_mode` default based on output types
- [x] `required_model_capability` - returns `@capability`
- [x] `declared_reads(prefix_schema = {})` - returns `@input_types`
- [x] `declared_sets(prefix_schema = {})` - returns `@output_types`
- [x] `create` - returns callable that:
  - [x] Gets adapter via `ProviderAdapters.for(model_config.provider)`
  - [x] Builds context from namespace (images marked as placeholders)
  - [x] Extracts images from namespace
  - [x] Renders template with `Mustache.render(template, context)`
  - [x] Calls `adapter.call(prompt:, model_config:, images:, json_mode:)`
  - [x] For image outputs: uses `adapter.extract_image`
  - [x] For text outputs: parses JSON, validates, merges into namespace

### Task 19.3: Add template loading
**File:** `lib/brainpipe/operations/llm_call.rb`

- [x] `load_template(options)` private method
  - [x] If `prompt` key, return string directly
  - [x] If `prompt_file` key, read file relative to config path
  - [x] Raise ConfigurationError if neither present

### Task 19.4: Add LlmCall require
**File:** `lib/brainpipe.rb`

- [x] Add `require "mustache"` (guarded or in operation file)
- [x] Add `require_relative "brainpipe/operations/llm_call"`

### Task 19.5: Update loader for LlmCall
**File:** `lib/brainpipe/loader.rb`

- [x] Ensure `Brainpipe::Operations::LlmCall` is resolvable
- [x] Validate `capability` is present and valid
- [x] Validate model has required capability

### Task 19.6: Test LlmCall operation
**File:** `spec/brainpipe/operations/llm_call_spec.rb`

- [x] Test `required_model_capability` returns configured capability
- [x] Test `declared_reads` returns input types
- [x] Test `declared_sets` returns output types
- [x] Test template loading from inline `prompt`
- [x] Test template loading from `prompt_file`
- [x] Test Mustache interpolation of variables
- [x] Test Mustache section iteration for arrays
- [x] Test image input handling (placeholder in context, extracted separately)
- [x] Test text output parsing and validation
- [x] Test image output extraction via adapter
- [x] Test json_mode default behavior

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

- [x] Directory structure created

### Task 20.2: Create model config
**File:** `examples/entity_extractor/config/brainpipe/config.yml`

- [x] Configure `openai` model
- [x] Configure `anthropic` model
- [x] Configure `gemini` model

### Task 20.3: Create pipeline config
**File:** `examples/entity_extractor/config/brainpipe/pipes/entity_extractor.yml`

- [x] Define `extract` stage with LlmCall operation
- [x] Set capability: `text_to_text`
- [x] Reference prompt template file

### Task 20.4: Create prompt template
**File:** `examples/entity_extractor/prompts/extract_entities.mustache`

- [x] Mustache template with `{{{ input_text }}}` interpolation
- [x] Section for entity_types iteration
- [x] JSON output instructions

### Task 20.5: Create demo script
**File:** `examples/entity_extractor/run.rb`

- [x] Load Brainpipe configuration
- [x] Run pipeline with sample text
- [x] Print extracted entities

### Task 20.6: Test example end-to-end
**Manual test:**
```bash
cd examples/entity_extractor
export OPENAI_API_KEY=your-key
bundle exec ruby run.rb
```

- [x] Verify entities printed to console
- [x] Test switching to different provider (anthropic, gemini)

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

## Phase 21: Transformation Operations (Link, Collapse, Explode)

### Prerequisites

#### Task 21.0.1: Update Executor for count-changing operations
**File:** `lib/brainpipe/executor.rb`

- [x] Update `validate_output_count!` to check `operation.allows_count_change?`
- [x] Skip count validation when `allows_count_change?` returns true
- [x] FR-2.12, FR-2.13

#### Task 21.0.2: Add stage validation for count-changing operations
**File:** `lib/brainpipe/stage.rb`

- [ ] Add validation that warns/errors when count-changing operations share a stage
- [ ] FR-2.14: Count-changing operations should be alone in their stage (optional enhancement)

---

### Task 21.1: Create Link operation
**File:** `lib/brainpipe/operations/link.rb`

Link rewires namespace properties without changing namespace count.

- [x] `initialize(model: nil, options: {})`
  - [x] Parse `copy:`, `move:`, `set:`, `delete:` options
  - [x] Normalize string keys to symbols
  - [x] Raise `ConfigurationError` if no operation specified (FR-13.1.6)
- [x] `allows_count_change?` returns `false` (FR-13.1.5)
- [x] `declared_reads(prefix_schema = {})`
  - [x] Return fields being copied or moved
  - [x] Look up types from prefix_schema
- [x] `declared_sets(prefix_schema = {})`
  - [x] Return target fields from copy, move, set
  - [x] Preserve type from source for copy/move
  - [x] Infer type from value for set
- [x] `declared_deletes(prefix_schema = {})`
  - [x] Return explicit delete fields + move source fields
- [x] `create` returns callable that:
  - [x] Applies operations in order: copy → move → set → delete (FR-13.1.7)
  - [x] Processes each namespace independently
  - [x] Preserves fields not involved in any operation

**Requirements:** FR-13.1.1 through FR-13.1.7

---

### Task 21.2: Create Collapse operation
**File:** `lib/brainpipe/operations/collapse.rb`

Collapse merges N namespaces into 1 with configurable per-field merge strategies.

- [x] `initialize(model: nil, options: {})`
  - [x] Parse `merge:` option with per-field strategies
  - [x] Parse Link options (`copy:`, `move:`, `set:`, `delete:`)
  - [x] Normalize string keys to symbols
  - [x] Validate merge strategies (error on unknown)
- [x] `MERGE_STRATEGIES` constant: `:collect`, `:sum`, `:concat`, `:first`, `:last`, `:equal`, `:distinct`
- [x] `allows_count_change?` returns `true` (FR-13.2.7)
- [x] `declared_reads(prefix_schema = {})`
  - [x] Return all fields from prefix_schema (we're collapsing everything)
- [x] `declared_sets(prefix_schema = {})`
  - [x] Return all fields from prefix_schema after collapse
  - [x] Change type to array for `:collect` and `:distinct` strategies
  - [x] Include Link set operations and move targets
- [x] `declared_deletes(prefix_schema = {})`
  - [x] Include Link delete fields and move source fields
- [x] `create` returns callable that:
  - [x] Merges N namespaces into 1 (FR-13.2.1)
  - [x] Applies per-field merge strategies (FR-13.2.2)
  - [x] Defaults to `:equal` strategy (FR-13.2.3)
  - [x] Implements all strategies:
    - [x] `:collect` - gather all values into array
    - [x] `:sum` - add numeric values
    - [x] `:concat` - concatenate strings or arrays
    - [x] `:first` - take first value
    - [x] `:last` - take last value
    - [x] `:equal` - all must match, raise ExecutionError otherwise
    - [x] `:distinct` - all must be unique, raise ExecutionError on duplicates
  - [x] Applies Link operations after merging (FR-13.2.6)
  - [x] Handles nil/missing values appropriately
  - [x] Returns single empty namespace for empty input

**Requirements:** FR-13.2.1 through FR-13.2.7

---

### Task 21.3: Create Explode operation
**File:** `lib/brainpipe/operations/explode.rb`

Explode fans out array fields from 1 namespace into N namespaces.

- [x] `initialize(model: nil, options: {})`
  - [x] Parse `split:` option (required, FR-13.3.1)
  - [x] Parse `on_empty:` option (`:skip` or `:error`, default `:skip`) (FR-13.3.6)
  - [x] Parse Link options (`copy:`, `move:`, `set:`, `delete:`)
  - [x] Normalize string keys to symbols
  - [x] Raise `ConfigurationError` if `split:` not specified
  - [x] Raise `ConfigurationError` for invalid `on_empty:` value
- [x] `allows_count_change?` returns `true` (FR-13.3.7)
- [x] `declared_reads(prefix_schema = {})`
  - [x] Return split source fields
  - [x] Look up types from prefix_schema
- [x] `declared_sets(prefix_schema = {})`
  - [x] Return split target fields with element type (unwrap array)
  - [x] Include non-split fields from prefix_schema (implicitly copied) (FR-13.3.3)
  - [x] Include Link set operations and move targets
  - [x] Exclude split source fields from output
- [x] `declared_deletes(prefix_schema = {})`
  - [x] Include split source fields (they're transformed)
  - [x] Include Link delete fields and move source fields
- [x] `create` returns callable that:
  - [x] Splits array fields into individual namespaces (FR-13.3.1)
  - [x] Validates same cardinality for multiple split fields (FR-13.3.2)
  - [x] Copies non-split fields to all output namespaces (FR-13.3.3)
  - [x] Applies Link operations after splitting (FR-13.3.5)
  - [x] Handles `on_empty: :skip` - returns empty array
  - [x] Handles `on_empty: :error` - raises ExecutionError
  - [x] Processes multiple input namespaces independently
  - [x] Preserves complex values in split and copied fields

**Requirements:** FR-13.3.1 through FR-13.3.7

---

### Task 21.4: Add requires
**File:** `lib/brainpipe.rb`

- [x] Add `require_relative "brainpipe/operations/link"`
- [x] Add `require_relative "brainpipe/operations/collapse"`
- [x] Add `require_relative "brainpipe/operations/explode"`

---

### Task 21.5: Mark deprecated operations
**File:** `lib/brainpipe/operations/transform.rb`

- [x] Add deprecation warning in initialize: "Transform is deprecated, use Link instead"

**File:** `lib/brainpipe/operations/merge.rb`

- [x] Add deprecation warning in initialize: "Merge is deprecated, use Collapse instead"

---

### Task 21.6: Run existing specs
**Files:** Spec files already staged

- [x] Run `bundle exec rspec spec/brainpipe/operations/link_spec.rb`
- [x] Run `bundle exec rspec spec/brainpipe/operations/collapse_spec.rb`
- [x] Run `bundle exec rspec spec/brainpipe/operations/explode_spec.rb`
- [x] Ensure all specs pass

---

## Phase 22: Remove Stage Modes

Stage modes (merge, fan_out, batch) are being removed. The Explode, Collapse, and Filter operations now handle namespace count changes, making stage modes redundant.

### Task 22.1: Update Stage class
**File:** `lib/brainpipe/stage.rb`

- [ ] Remove `MODES` constant
- [ ] Remove `mode` attribute and parameter from `initialize`
- [ ] Remove `validate_mode!` method
- [ ] Remove `execute_merge`, `execute_fan_out`, `execute_batch` methods
- [ ] Simplify `execute_stage` to pass namespace array directly to operations
- [ ] Remove `MERGE_STRATEGIES` constant
- [ ] Remove `merge_strategy` attribute and parameter
- [ ] Remove merge strategy methods (`merge_at_index`, `merge_last_in`, `merge_first_in`, `merge_collate`, `merge_disjoint`)
- [ ] Remove `validate_disjoint!` method

### Task 22.2: Update Pipe class
**File:** `lib/brainpipe/pipe.rb`

- [ ] Remove `validate_last_stage_mode!` method
- [ ] Remove call to `validate_last_stage_mode!` in `validate!`

### Task 22.3: Update Loader
**File:** `lib/brainpipe/loader.rb`

- [ ] Remove `mode:` parsing from stage YAML
- [ ] Remove `merge_strategy:` parsing from stage YAML
- [ ] Update Stage constructor call to not pass mode/merge_strategy

### Task 22.4: Update example YAML files
Remove `mode:` from all pipeline configurations:

- [ ] `examples/data_transformer/config/brainpipe/pipes/data_transformer.yml`
- [ ] `examples/entity_extractor/config/brainpipe/pipes/entity_extractor.yml`
- [ ] `examples/image_fixer/config/brainpipe/pipes/image_fixer.yml`
- [ ] `examples/rails_app/config/brainpipe/echo.yml`

### Task 22.5: Update Stage specs
**File:** `spec/brainpipe/stage_spec.rb`

- [ ] Remove mode validation tests
- [ ] Remove merge strategy tests
- [ ] Remove mode-specific execution tests (merge mode, fan_out mode, batch mode contexts)
- [ ] Update all `described_class.new` calls to not pass `mode:`
- [ ] Add tests for simplified stage execution (operations receive full namespace array)

### Task 22.6: Update Pipe specs
**File:** `spec/brainpipe/pipe_spec.rb`

- [ ] Remove "last stage mode" context and tests
- [ ] Update `create_stage` helper to not require `mode:` parameter
- [ ] Update all test stage creations

### Task 22.7: Update Loader specs
**File:** `spec/brainpipe/loader_spec.rb`

- [ ] Remove assertions checking `stage.mode`
- [ ] Update test YAML fixtures to not include `mode:`

### Task 22.8: Update other specs
- [ ] `spec/brainpipe/operations/integration_spec.rb` - Update stage creation
- [ ] `spec/brainpipe/observability/integration_spec.rb` - Update stage creation
- [ ] `spec/brainpipe/observability/debug_spec.rb` - Update stage creation
- [ ] `spec/brainpipe/type_flow_spec.rb` - Update stage creation
- [ ] `spec/brainpipe/executor_spec.rb` - Update if needed

### Task 22.9: Update README.md
**File:** `README.md`

- [ ] Remove "Stages" section content about modes (merge, fan_out, batch)
- [ ] Remove `mode:` from all YAML examples
- [ ] Remove merge strategy documentation
- [ ] Update stage documentation to explain simplified model
- [ ] Update "Data Transformation Example" to show simpler config without modes

### Task 22.10: Update EXAMPLE.md
**File:** `EXAMPLE.md`

- [ ] Remove `mode: merge` from all pipeline YAML examples

### Task 22.11: Run full test suite
- [ ] Run `bundle exec rspec` and fix any failures

### Task 22.12: Run example scripts
- [ ] Run `examples/entity_extractor/run.rb` and verify it works
- [ ] Run `examples/data_transformer/run.rb` and verify it works
- [ ] Run `examples/image_fixer/run.rb` and verify it works (requires GOOGLE_AI_API_KEY)

---

## Final Tasks

- [ ] Review all public API for consistency
- [ ] Ensure all errors have useful messages
- [ ] Add YARD documentation to public methods
- [ ] Update README with usage examples
- [ ] Update CHANGELOG.md
- [x] Verify gemspec metadata
- [x] Test gem installation from local build
