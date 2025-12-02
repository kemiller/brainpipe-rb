# Example: Image Fixer Pipeline

A two-stage pipeline that analyzes image problems and fixes them using Gemini models.

## Pipeline Flow

```
Input Image → [Analyze Problems] → [Fix Image] → Fixed Image
                 (Gemini)         (Gemini Flash Image)
```

## Directory Structure

```
examples/image_fixer/
├── baml_src/
│   └── image_fixer.baml     # BAML function definitions
├── config/
│   └── brainpipe/
│       ├── config.yml       # Model configuration
│       └── pipes/
│           └── image_fixer.yml  # Pipeline definition
└── run.rb                   # Demo script
```

---

## Configuration

### config/brainpipe/config.yml

```yaml
models:
  gemini:
    provider: google_ai
    model: gemini-2.0-flash
    capabilities:
      - text_to_text
      - image_to_text
    options:
      api_key: ${GOOGLE_AI_API_KEY}

  gemini_flash_image:
    provider: google_ai
    model: gemini-2.5-flash-preview-04-17
    capabilities:
      - image_edit
    options:
      api_key: ${GOOGLE_AI_API_KEY}
```

### config/brainpipe/pipes/image_fixer.yml

```yaml
name: image_fixer

stages:
  - name: analyze
    operations:
      - type: Brainpipe::Operations::Baml
        model: gemini
        options:
          function: AnalyzeImageProblems
          inputs:
            img: input_image
          outputs:
            problems: problems
            fix_instructions: fix_instructions

  - name: fix
    operations:
      - type: Brainpipe::Operations::BamlRaw
        model: gemini_flash_image
        options:
          function: FixImageProblems
          inputs:
            img: input_image
            instructions: fix_instructions
          image_extractor: Brainpipe::Extractors::GeminiImage
          output_field: fixed_image
```

---

## BAML Functions

### baml_src/image_fixer.baml

```baml
class Problem {
  type string @description("exposure, color, noise, blur, composition, artifacts")
  description string
  location string @description("center, edges, background, foreground, overall")
}

class ImageAnalysis {
  problems Problem[]
  fix_instructions string @description("Consolidated instructions for fixing all problems")
}

function AnalyzeImageProblems(img: image) -> ImageAnalysis {
  client Gemini
  prompt #"
    {{ _.role("user") }}
    Analyze this image for quality problems.

    Check for:
    - Exposure issues (over/underexposed)
    - Color balance problems
    - Noise or grain
    - Blur or focus issues
    - Composition problems
    - Compression artifacts

    {{ img }}

    Return a structured analysis with specific fix instructions.
  "#
}

function FixImageProblems(img: image, instructions: string) -> string {
  client GeminiFlashImage
  prompt #"
    {{ _.role("user") }}
    Fix this image according to these instructions:

    {{ instructions }}

    {{ img }}

    Generate an improved version of the image.
  "#
}
```

---

## Demo Script

### run.rb

```ruby
#!/usr/bin/env ruby
require "brainpipe"
require "base64"

# Load configuration
Brainpipe.configure do |c|
  c.config_path = "config/brainpipe"
end
Brainpipe.load!

# Get the pipeline
pipe = Brainpipe.pipe(:image_fixer)

# Load input image
input_path = ARGV[0] || "sample.jpg"
input_image = Brainpipe::Image.from_file(input_path)

puts "Analyzing and fixing: #{input_path}"

# Run the pipeline
result = pipe.call(input_image: input_image)

# Output results
puts "\n=== Analysis ==="
result[:problems].each do |problem|
  puts "- #{problem[:type]}: #{problem[:description]} (#{problem[:location]})"
end

puts "\n=== Fix Instructions ==="
puts result[:fix_instructions]

# Save fixed image
if result[:fixed_image]
  output_path = "fixed_#{File.basename(input_path, '.*')}.png"
  File.binwrite(output_path, Base64.decode64(result[:fixed_image].base64))
  puts "\n=== Output ==="
  puts "Fixed image saved to: #{output_path}"
else
  puts "\nNo image was generated."
end
```

---

## Running the Example

```bash
cd examples/image_fixer

# Set API key
export GOOGLE_AI_API_KEY=your-key-here

# Run with default sample image
ruby run.rb

# Run with custom image
ruby run.rb /path/to/your/image.jpg
```

---

# Example: Entity Extractor with LlmCall

A single-stage pipeline using LlmCall for direct LLM calls without BAML. Demonstrates provider-agnostic Mustache templating with JSON output parsing.

## Pipeline Flow

```
Input Text → [Extract Entities] → Entities + Summary
                (LlmCall)
```

## Directory Structure

```
examples/entity_extractor/
├── config/
│   └── brainpipe/
│       ├── config.yml           # Model configuration
│       └── pipes/
│           └── entity_extractor.yml  # Pipeline definition
├── prompts/
│   └── extract_entities.mustache    # Mustache template file
└── run.rb                       # Demo script
```

---

## Configuration

### config/brainpipe/config.yml

```yaml
models:
  openai:
    provider: openai
    model: gpt-4o
    capabilities:
      - text_to_text
    options:
      api_key: ${OPENAI_API_KEY}

  anthropic:
    provider: anthropic
    model: claude-3-5-sonnet-20241022
    capabilities:
      - text_to_text
    options:
      api_key: ${ANTHROPIC_API_KEY}

  gemini:
    provider: google_ai
    model: gemini-2.0-flash
    capabilities:
      - text_to_text
    options:
      api_key: ${GOOGLE_AI_API_KEY}
```

### config/brainpipe/pipes/entity_extractor.yml

```yaml
name: entity_extractor

stages:
  - name: extract
    operations:
      - type: Brainpipe::Operations::LlmCall
        model: openai  # Can swap to anthropic or gemini
        options:
          capability: text_to_text
          prompt_file: prompts/extract_entities.mustache
          inputs:
            input_text: String
            entity_types: [String]
          outputs:
            entities: [{ name: String, type: String, confidence: Float }]
            summary: String
            entity_count: Integer
```

### prompts/extract_entities.mustache

```mustache
You are an entity extraction system. Analyze the following text and extract named entities.

Text to analyze:
{{{ input_text }}}

Entity types to look for:
{{# entity_types }}
- {{ . }}
{{/ entity_types }}

Return a JSON object with exactly this structure:
{
  "entities": [
    {"name": "entity name", "type": "entity type", "confidence": 0.95}
  ],
  "summary": "Brief summary of the text",
  "entity_count": 5
}

Rules:
- Only include entities with confidence >= 0.7
- Type must be one of the requested entity types
- Summary should be 1-2 sentences max
```

---

## Demo Script

### run.rb

```ruby
#!/usr/bin/env ruby
require "brainpipe"

# Load configuration
Brainpipe.configure do |c|
  c.config_path = "config/brainpipe"
end
Brainpipe.load!

# Get the pipeline
pipe = Brainpipe.pipe(:entity_extractor)

# Sample input
input_text = <<~TEXT
  Apple Inc. announced today that CEO Tim Cook will present the new iPhone 16
  at their headquarters in Cupertino, California. The event, scheduled for
  September 2024, is expected to draw attention from investors on Wall Street.
  Microsoft and Google representatives were also spotted at the venue.
TEXT

entity_types = ["PERSON", "ORGANIZATION", "LOCATION", "DATE", "PRODUCT"]

puts "=== Input ==="
puts input_text
puts

# Run the pipeline
result = pipe.call(
  input_text: input_text,
  entity_types: entity_types
)

# Output results
puts "=== Extracted Entities ==="
result[:entities].each do |entity|
  puts "- #{entity[:name]} (#{entity[:type]}) - confidence: #{entity[:confidence]}"
end

puts "\n=== Summary ==="
puts result[:summary]

puts "\n=== Stats ==="
puts "Total entities found: #{result[:entity_count]}"
```

---

## Running the Example

```bash
cd examples/entity_extractor

# Set API key (pick one provider)
export OPENAI_API_KEY=your-key-here
# OR
export ANTHROPIC_API_KEY=your-key-here
# OR
export GOOGLE_AI_API_KEY=your-key-here

# Run
ruby run.rb
```

## Expected Output

```
=== Input ===
Apple Inc. announced today that CEO Tim Cook will present the new iPhone 16
at their headquarters in Cupertino, California. The event, scheduled for
September 2024, is expected to draw attention from investors on Wall Street.
Microsoft and Google representatives were also spotted at the venue.

=== Extracted Entities ===
- Apple Inc. (ORGANIZATION) - confidence: 0.98
- Tim Cook (PERSON) - confidence: 0.97
- iPhone 16 (PRODUCT) - confidence: 0.95
- Cupertino (LOCATION) - confidence: 0.96
- California (LOCATION) - confidence: 0.97
- September 2024 (DATE) - confidence: 0.94
- Wall Street (LOCATION) - confidence: 0.89
- Microsoft (ORGANIZATION) - confidence: 0.95
- Google (ORGANIZATION) - confidence: 0.96

=== Summary ===
Apple Inc. is hosting a product launch event featuring the iPhone 16, presented by Tim Cook in Cupertino, California in September 2024.

=== Stats ===
Total entities found: 9
```

## Switching Providers

The same pipeline works with any provider—just change the `model` reference in the YAML:

```yaml
# Use Anthropic instead
- type: Brainpipe::Operations::LlmCall
  model: anthropic  # Changed from openai
  options:
    capability: text_to_text
    prompt_file: prompts/extract_entities.mustache
    # ... same inputs/outputs
```

The provider adapter handles all marshalling automatically based on the model's `provider` field.

---

# Example: Image Description with LlmCall (Vision)

Demonstrates LlmCall with image input using the `image_to_text` capability.

## Pipeline Flow

```
Input Image → [Describe Image] → Description + Tags
                 (LlmCall)
```

## Configuration

### config/brainpipe/pipes/image_describer.yml

```yaml
name: image_describer

stages:
  - name: describe
    operations:
      - type: Brainpipe::Operations::LlmCall
        model: gpt4_vision
        options:
          capability: image_to_text
          prompt: |
            Analyze this image and provide a detailed description.

            {{{ input_image }}}

            Return a JSON object:
            {
              "description": "detailed description of the image",
              "objects": ["list", "of", "objects"],
              "colors": ["dominant", "colors"],
              "mood": "overall mood/feeling"
            }
          inputs:
            input_image: Brainpipe::Image
          outputs:
            description: String
            objects: [String]
            colors: [String]
            mood: String
```

### run.rb

```ruby
#!/usr/bin/env ruby
require "brainpipe"

Brainpipe.load!
pipe = Brainpipe.pipe(:image_describer)

# Load image
image = Brainpipe::Image.from_file("photo.jpg")

result = pipe.call(input_image: image)

puts "Description: #{result[:description]}"
puts "Objects: #{result[:objects].join(', ')}"
puts "Colors: #{result[:colors].join(', ')}"
puts "Mood: #{result[:mood]}"
```

---

# Example: Image Generation with LlmCall

Demonstrates LlmCall with image output using the `text_to_image` capability.

## Configuration

### config/brainpipe/pipes/image_generator.yml

```yaml
name: image_generator

stages:
  - name: generate
    operations:
      - type: Brainpipe::Operations::LlmCall
        model: gemini_imagen
        options:
          capability: text_to_image
          prompt: |
            Generate an image with the following characteristics:

            Subject: {{{ subject }}}
            Style: {{{ style }}}
            Mood: {{{ mood }}}
          inputs:
            subject: String
            style: String
            mood: String
          outputs:
            generated_image: Brainpipe::Image
          # image_extractor not needed - GoogleAI adapter handles it automatically
```

### run.rb

```ruby
#!/usr/bin/env ruby
require "brainpipe"

Brainpipe.load!
pipe = Brainpipe.pipe(:image_generator)

result = pipe.call(
  subject: "a cat wearing a space helmet",
  style: "watercolor painting",
  mood: "whimsical and playful"
)

# Save the generated image
File.binwrite("output.png", Base64.decode64(result[:generated_image].base64))
puts "Image saved to output.png"
```
