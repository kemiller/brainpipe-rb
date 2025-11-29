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

    {{ ctx.output_format }}
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

client<llm> Gemini {
  provider google-ai
  options {
    api_key env.GOOGLE_AI_API_KEY
    model "gemini-2.0-flash"
  }
}

client<llm> GeminiFlashImage {
  provider google-ai
  options {
    api_key env.GOOGLE_AI_API_KEY
    model "gemini-2.0-flash-exp"
    generationConfig {
      responseModalities ["TEXT", "IMAGE"]
    }
  }
}
