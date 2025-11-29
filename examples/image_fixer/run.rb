#!/usr/bin/env ruby
$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "brainpipe"
require "base64"

Dir.chdir(__dir__)
require_relative "baml_client/client"

Brainpipe.configure do |c|
  c.config_path = "config/brainpipe"
end
Brainpipe.load!

pipe = Brainpipe.pipe(:image_fixer)

input_path = ARGV[0] || "sample.jpg"
unless File.exist?(input_path)
  puts "Error: Image file not found: #{input_path}"
  puts "Usage: ruby run.rb [path/to/image.jpg]"
  exit 1
end

input_image = Brainpipe::Image.from_file(input_path)

puts "Analyzing and fixing: #{input_path}"
puts

result = pipe.call(input_image: input_image)

puts "=== Analysis ==="
if result[:problems]
  result[:problems].each do |problem|
    type = problem[:type] || problem["type"]
    desc = problem[:description] || problem["description"]
    loc = problem[:location] || problem["location"]
    puts "- #{type}: #{desc} (#{loc})"
  end
else
  puts "No problems detected."
end

puts
puts "=== Fix Instructions ==="
puts result[:fix_instructions] || "No instructions provided."

if result[:fixed_image]
  ext = File.extname(input_path)
  basename = File.basename(input_path, ext)
  output_path = "fixed_#{basename}.png"
  File.binwrite(output_path, Base64.decode64(result[:fixed_image].base64))
  puts
  puts "=== Output ==="
  puts "Fixed image saved to: #{output_path}"
else
  puts
  puts "No image was generated."
end
