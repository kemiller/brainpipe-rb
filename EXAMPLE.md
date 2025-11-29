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
    mode: merge
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
    mode: merge
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
