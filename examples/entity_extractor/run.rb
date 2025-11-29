#!/usr/bin/env ruby
$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "brainpipe"

Dir.chdir(__dir__)

Brainpipe.configure do |c|
  c.config_path = "config/brainpipe"
end
Brainpipe.load!

pipe = Brainpipe.pipe(:entity_extractor)

sample_text = ARGV[0] || <<~TEXT
  Apple Inc. announced today that CEO Tim Cook will be visiting their new
  headquarters in Cupertino, California next week. The tech giant, founded
  by Steve Jobs in 1976, reported quarterly revenue of $89.5 billion.
  Microsoft CEO Satya Nadella congratulated Apple on their results during
  a conference in Seattle, Washington.
TEXT

entity_types = %w[PERSON ORGANIZATION LOCATION]

puts "=== Input Text ==="
puts sample_text
puts
puts "=== Entity Types ==="
puts entity_types.join(", ")
puts

result = pipe.call(input_text: sample_text, entity_types: entity_types)

puts "=== Extracted Entities ==="
if result[:entities] && !result[:entities].empty?
  result[:entities].each do |entity|
    name = entity["name"] || entity[:name]
    type = entity["type"] || entity[:type]
    confidence = entity["confidence"] || entity[:confidence]
    puts "- #{name} (#{type}) [confidence: #{confidence}]"
  end
else
  puts "No entities found."
end

puts
puts "=== Summary ==="
puts result[:summary] || "No summary provided."
