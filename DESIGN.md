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

### Image Type

The `Image` type is a flexible wrapper supporting both URL and base64 representations with lazy conversion.

**Construction:**
```ruby
# From URL (lazy - base64 fetched on demand)
image = Brainpipe::Image.from_url("https://example.com/photo.jpg")

# From base64
image = Brainpipe::Image.from_base64(data, mime_type: "image/png")

# From file
image = Brainpipe::Image.from_file("path/to/photo.jpg")
```

**Interface:**
```ruby
class Brainpipe::Image
  attr_reader :mime_type

  def url?          # true if constructed from URL
  def base64?       # true if base64 data is available
  def url           # returns URL or raises if base64-only
  def base64        # returns base64 data, fetching from URL if needed
end

# BAML conversion via adapter (see BamlAdapter section)
BamlAdapter.to_baml_image(image)  # converts to Baml::Image
```

**MIME Type Inference:**
- `.png` → `image/png`
- `.jpg`, `.jpeg` → `image/jpeg`
- `.gif` → `image/gif`
- `.webp` → `image/webp`

Image instances are frozen after construction. URL-to-base64 conversion caches the result internally.

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

### BamlRaw Operation

For cases where BAML cannot parse the LLM response (e.g., image outputs), use `BamlRaw` to access raw HTTP responses via BAML's Modular API.

**Usage:**
```yaml
operations:
  - type: Brainpipe::Operations::BamlRaw
    model: gemini_flash
    options:
      function: FixImageProblems
      inputs:
        img: input_image
        instructions: fix_instructions
      image_extractor: Brainpipe::Extractors::GeminiImage
```

**How It Works:**
1. Builds input from namespace using the `inputs` mapping
2. Uses BAML's Modular API: `Baml::Client.request.FunctionName(**input)` to get raw request
3. Executes HTTP request directly using Net::HTTP
4. Passes raw JSON response to the configured `image_extractor`
5. Extractor returns an `Image` instance that's merged into namespace

**BAML Modular API (Ruby):**
```ruby
# Get raw request from BAML
baml_req = Baml::Client.request.FunctionName(**input)

# Execute manually
uri = URI.parse(baml_req.url)
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = uri.scheme == "https"

req = Net::HTTP::Post.new(uri.path)
baml_req.headers.each { |k, v| req[k] = v }
req.body = baml_req.body.json.to_json

response = http.request(req)
raw_json = JSON.parse(response.body)
```

**Configuration Options:**

| Option | Required | Description |
|--------|----------|-------------|
| `function` | Yes | BAML function name |
| `inputs` | No | Map BAML params to namespace fields |
| `image_extractor` | Yes | Class/module with `.call(response)` returning Image |
| `output_field` | No | Namespace field for extracted image (default: `:output_image`) |

### Image Extractors

Extractors parse raw LLM responses to extract image data.

**GeminiImage Extractor:**
```ruby
module Brainpipe::Extractors::GeminiImage
  def self.call(response)
    parts = response.dig("candidates", 0, "content", "parts") || []

    parts.each do |part|
      if (data = part["inlineData"])
        return Brainpipe::Image.from_base64(
          data["data"],
          mime_type: data["mimeType"]
        )
      end
    end

    nil
  end
end
```

**Custom Extractors:**
```ruby
module MyExtractor
  def self.call(response)
    base64_data = response.dig("output", "image_base64")
    Brainpipe::Image.from_base64(base64_data, mime_type: "image/png")
  end
end
```

### LlmCall Operation

For direct LLM calls without BAML, using Mustache templates with variable interpolation. Provider-agnostic with automatic adapter selection. Supports all capability types including multimodal (image input/output).

**Text-to-Text Example:**
```yaml
operations:
  - type: Brainpipe::Operations::LlmCall
    model: gemini
    options:
      capability: text_to_text
      prompt: |
        Analyze this text and extract key entities.

        Text: {{{ input_text }}}

        Return a JSON object with:
        - entities: array of {name, type, confidence}
        - summary: brief summary string
      inputs:
        input_text: String
      outputs:
        entities: [{ name: String, type: String, confidence: Float }]
        summary: String
```

**Image-to-Text (Vision) Example:**
```yaml
operations:
  - type: Brainpipe::Operations::LlmCall
    model: gpt4_vision
    options:
      capability: image_to_text
      prompt: |
        Describe this image in detail.

        {{{ input_image }}}

        Return JSON with: {"description": "...", "objects": ["...", "..."]}
      inputs:
        input_image: Brainpipe::Image
      outputs:
        description: String
        objects: [String]
```

**Text-to-Image (Generation) Example:**
```yaml
operations:
  - type: Brainpipe::Operations::LlmCall
    model: gemini_image_gen
    options:
      capability: text_to_image
      prompt: |
        Generate an image based on this description:

        {{{ prompt_text }}}

        Style: {{{ style }}}
      inputs:
        prompt_text: String
        style: String
      outputs:
        generated_image: Brainpipe::Image
      # Adapter's extract_image used automatically for google_ai provider
```

**Image-to-Image (Edit) Example:**
```yaml
operations:
  - type: Brainpipe::Operations::LlmCall
    model: gemini_flash_image
    options:
      capability: image_edit
      prompt: |
        Edit this image according to the instructions:

        {{{ source_image }}}

        Instructions: {{{ edit_instructions }}}
      inputs:
        source_image: Brainpipe::Image
        edit_instructions: String
      outputs:
        edited_image: Brainpipe::Image
      # image_extractor: MyCustomExtractor  # Optional override if needed
```

**With template file:**
```yaml
operations:
  - type: Brainpipe::Operations::LlmCall
    model: openai_gpt4
    options:
      capability: text_to_text
      prompt_file: prompts/extract_entities.mustache
      inputs:
        input_text: String
        language: String
      outputs:
        entities: [{ name: String, type: String }]
```

**How It Works:**
1. Loads prompt template from `prompt` string or `prompt_file` path
2. Renders template using Mustache with namespace values
3. Selects provider adapter based on model config (openai, anthropic, google_ai)
4. Adapter marshals request to provider-specific format, handling images appropriately
5. Adapter executes HTTP call and returns raw response
6. For text outputs: adapter extracts text, parses as JSON, validates against schema
7. For image outputs: adapter extracts image (or uses optional `image_extractor` override)
8. Merges validated output into namespace

**Configuration Options:**

| Option | Required | Description |
|--------|----------|-------------|
| `capability` | Yes | Required capability (text_to_text, image_to_text, text_to_image, image_edit) |
| `prompt` | Yes* | Inline Mustache template |
| `prompt_file` | Yes* | Path to Mustache template file (relative to config dir) |
| `inputs` | Yes | Map of input variable names to types |
| `outputs` | Yes | Map of output variable names to types |
| `image_extractor` | No | Override adapter's default image extractor (rarely needed) |
| `json_mode` | No | Force JSON response mode if provider supports it (default: true for text outputs) |

*One of `prompt` or `prompt_file` is required.

**Mustache Template Syntax:**

Uses standard Mustache syntax (via the `mustache` gem):

```mustache
{{ variable }}              # HTML-escaped interpolation
{{{ variable }}}            # Unescaped interpolation (use for text content)
{{# list }}...{{/ list }}   # Section (iteration)
{{^ flag }}...{{/ flag }}   # Inverted section (if falsy)
```

For Image inputs, the adapter handles rendering appropriately for the provider.

**Provider Adapters:**

Provider adapters handle all provider-specific concerns: request marshalling, response parsing, text extraction, and image extraction. Each adapter knows how to work with its provider's API format.

Adapters are selected automatically based on `model_config.provider`. For image outputs, the adapter's built-in image extractor is used by default, with an optional override via `image_extractor`.

```ruby
module Brainpipe::ProviderAdapters
  class Base
    def call(prompt:, model_config:, images: [], json_mode: false)
      raise NotImplementedError
    end

    def extract_text(response)
      raise NotImplementedError
    end

    def extract_image(response)
      nil  # Override in adapters that support image output
    end
  end

  class OpenAI < Base
    def call(prompt:, model_config:, images: [], json_mode: false)
      # Build OpenAI chat completion request
      # Handle images as base64 in content array
      # Set response_format: {type: "json_object"} if json_mode
    end

    def extract_text(response)
      response.dig("choices", 0, "message", "content")
    end

    # OpenAI doesn't return images in chat completions (DALL-E uses different API)
  end

  class Anthropic < Base
    def call(prompt:, model_config:, images: [], json_mode: false)
      # Build Anthropic messages request
      # Handle images in content blocks
    end

    def extract_text(response)
      response.dig("content", 0, "text")
    end

    # Anthropic doesn't currently support image generation in messages API
  end

  class GoogleAI < Base
    def call(prompt:, model_config:, images: [], json_mode: false)
      # Build Google AI generateContent request
      # Handle images as inlineData parts
    end

    def extract_text(response)
      response.dig("candidates", 0, "content", "parts", 0, "text")
    end

    def extract_image(response)
      parts = response.dig("candidates", 0, "content", "parts") || []
      parts.each do |part|
        if (data = part["inlineData"])
          return Brainpipe::Image.from_base64(
            data["data"],
            mime_type: data["mimeType"]
          )
        end
      end
      nil
    end
  end
end
```

**Provider Symbol Convention:**

Brainpipe uses Ruby-idiomatic underscored symbols internally (`:google_ai`, `:openai`). When interfacing with BAML (which uses hyphenated strings like `"google-ai"`), conversion happens automatically:

```ruby
module Brainpipe::ProviderAdapters
  def self.normalize_provider(provider)
    # Accept either format, normalize to underscored symbol
    provider.to_s.tr("-", "_").to_sym
  end

  def self.to_baml_provider(provider)
    # Convert to BAML's hyphenated string format
    provider.to_s.tr("_", "-")
  end
end
```

In YAML configs, either format works:
```yaml
models:
  gemini:
    provider: google_ai    # Ruby style (preferred)
    # provider: google-ai  # BAML style (also accepted)
```

**Adapter Registry:**
```ruby
Brainpipe::ProviderAdapters.register(:openai, OpenAI)
Brainpipe::ProviderAdapters.register(:anthropic, Anthropic)
Brainpipe::ProviderAdapters.register(:google_ai, GoogleAI)

# Selection (normalizes provider name automatically)
adapter = Brainpipe::ProviderAdapters.for(model_config.provider)
```

Additional providers (Vertex, Bedrock, Azure) can be added via pull request as needed.

**Ruby Implementation:**
```ruby
require "mustache"

class Brainpipe::Operations::LlmCall < Operation
  def initialize(model: nil, options: {})
    super
    @prompt_template = load_template(options)
    @capability = options[:capability]&.to_sym
    @input_types = options[:inputs] || {}
    @output_types = options[:outputs] || {}
    @image_extractor_override = resolve_extractor(options[:image_extractor])
    @json_mode = options.fetch(:json_mode, !has_image_output?)
  end

  def required_model_capability
    @capability
  end

  def declared_reads(prefix_schema = {})
    @input_types
  end

  def declared_sets(prefix_schema = {})
    @output_types
  end

  def create
    template = @prompt_template
    output_types = @output_types
    json_mode = @json_mode
    model_cfg = model_config
    extractor_override = @image_extractor_override
    image_output = has_image_output?

    ->(namespaces) {
      adapter = ProviderAdapters.for(model_cfg.provider)

      namespaces.map do |ns|
        context = build_context(ns)
        images = extract_images(ns)

        prompt = Mustache.render(template, context)

        response = adapter.call(
          prompt: prompt,
          model_config: model_cfg,
          images: images,
          json_mode: json_mode
        )

        if image_output
          # Use override extractor if provided, otherwise adapter's default
          image = if extractor_override
            extractor_override.call(response)
          else
            adapter.extract_image(response)
          end

          image_field = output_types.find { |_, t| t == Image || t.to_s.include?("Image") }&.first
          ns.merge(image_field => image)
        else
          text = adapter.extract_text(response)
          json = JSON.parse(text)
          validate_output!(json, output_types)
          ns.merge(json.transform_keys(&:to_sym))
        end
      end
    }
  end

  private

  def has_image_output?
    @output_types.values.any? { |t| t == Image || t.to_s.include?("Image") }
  end

  def build_context(namespace)
    namespace.to_h.transform_values do |value|
      case value
      when Image
        "[IMAGE]"  # Placeholder; actual image passed separately to adapter
      else
        value
      end
    end
  end

  def extract_images(namespace)
    namespace.to_h.select { |_, v| v.is_a?(Image) }
  end
end
```

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

### Type Flow & Schema Propagation

Types flow through the pipeline via the `declared_reads`/`declared_sets`/`declared_deletes` contract. Each operation receives the **prefix schema** (cumulative output types from all previous stages) when queried for its contract.

**Schema flow rule:**
```
stage_output_schema = prefix_schema - deletes + sets
```

Operations only declare what they explicitly touch; all other fields flow through unchanged.

**Pipeline validation walks stage-by-stage:**
1. Start with pipe input schema
2. For each stage, query each operation's `declared_sets(prefix_schema)` and `declared_deletes(prefix_schema)`
3. Compute new prefix: `prefix - deletes + sets`
4. Validate next stage's `declared_reads(prefix)` are satisfied
5. Repeat until end

**Type preservation for utility operations:**
- Transform/rename: looks up source field type from `prefix_schema`, declares same type for target
- Filter: declares only the fields it inspects; everything flows through
- Merge: must explicitly declare `target_type` since combining fields produces a new type

**Load-time type conflict detection:**

When multiple operations in a parallel stage set the same field, types must match:

```ruby
# Both operations set :result - types must be identical
stage:
  operations:
    - type: OpA  # sets :result, String
    - type: OpB  # sets :result, Integer  → TypeConflictError at load time
```

This is validated during pipe construction by comparing `declared_sets(prefix_schema)` across parallel operations.

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
  # prefix_schema is passed during pipeline validation to enable type lookup
  def declared_reads(prefix_schema = {})    # Returns { name: Type, ... }
  def declared_sets(prefix_schema = {})     # Returns { name: Type, ... }
  def declared_deletes(prefix_schema = {})  # Returns [name, ...]
  def required_model_capability # Returns capability symbol or nil
  def error_handler             # Returns nil, true, or Proc
end
```

**Instance-level resolution**: Property declarations are resolved on the *instance* after initialization. This enables:

```ruby
# Dynamic properties based on options - type preserved via prefix_schema lookup
class RenameField < Brainpipe::Operation
  def initialize(model: nil, options: {})
    super
    @from = options[:from]
    @to = options[:to]
  end

  # Type is looked up from prefix_schema, preserving the source field's type
  def declared_reads(prefix_schema = {}) = { @from => prefix_schema[@from] || Any }
  def declared_sets(prefix_schema = {}) = { @to => prefix_schema[@from] || Any }
  def declared_deletes(prefix_schema = {}) = [@from]

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
  def resolved_api_key            # Resolves API key from options via SecretResolver
end

# BAML conversion via adapter (see BamlAdapter section)
BamlAdapter.build_client_registry(model_config)  # converts to Baml::ClientRegistry
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
  class TypeConflictError < ConfigurationError; end  # parallel ops set same field with different types

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
- `mustache` - Template rendering for LlmCall operation

### Optional
- `baml` - BAML integration (runtime dependency)

---

## BamlAdapter

The `BamlAdapter` class is the **single point of contact** for all BAML interactions. Core models (`ModelConfig`, `Image`, etc.) must not directly reference BAML constants or require the BAML gem.

### Design Rationale

- BAML is an optional dependency; core models remain decoupled from any specific LLM adapter
- Future adapters (e.g., LangChain, LiteLLM) can be added without modifying core classes
- All `::Baml::*` references and `require "baml"` statements are confined to `baml_adapter.rb`

### Interface

```ruby
class BamlAdapter
  class << self
    def available?              # true if BAML gem is loadable
    def require_available!      # raises ConfigurationError if unavailable

    def function(name)          # returns BamlFunction wrapper
    def baml_client             # returns the BAML client (::Baml.Client or ::B)

    # Type conversions (core types → BAML types)
    def to_baml_image(image)                    # Image → Baml::Image
    def build_client_registry(model_config)     # ModelConfig → Baml::ClientRegistry

    def reset!                  # clears cached state (for testing)
  end
end

class BamlFunction
  attr_reader :name, :client

  def call(input, client_registry: nil)  # executes BAML function
  def input_schema                        # returns input schema hash
  def output_schema                       # returns output schema hash
end
```

### Usage in Operations

```ruby
# In BAML operations
class Brainpipe::Operations::Baml < Operation
  def create
    ->(namespaces) {
      namespaces.map do |ns|
        input = build_input(ns)
        registry = BamlAdapter.build_client_registry(model_config) if model_config
        result = @baml_function.call(input, client_registry: registry)
        ns.merge(map_outputs(result))
      end
    }
  end

  private

  def convert_for_baml(value)
    case value
    when Image then BamlAdapter.to_baml_image(value)
    else value
    end
  end
end
```

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
