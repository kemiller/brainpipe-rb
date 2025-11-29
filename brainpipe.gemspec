Gem::Specification.new do |spec|
  spec.name          = "brainpipe"
  spec.version       = "0.1.0"
  spec.authors       = ["Ken Miller"]
  spec.email         = ["ken.miller@gmail.com"]

  spec.summary       = "Type-safe, observable LLM pipelines with contract validation"
  spec.description   = "A Ruby gem for building type-safe, observable LLM pipelines with contract validation. " \
                       "Provides a declarative DSL for composing operations into pipelines with built-in support " \
                       "for parallel execution, type checking, and BAML integration."
  spec.homepage      = "https://github.com/kenmiller/brainpipe"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "concurrent-ruby", "~> 1.2"
  spec.add_dependency "zeitwerk", "~> 2.6"
end
