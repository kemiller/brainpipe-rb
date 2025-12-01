#!/usr/bin/env ruby
$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "brainpipe"

Dir.chdir(__dir__)

Brainpipe.configure do |c|
  c.config_path = "config/brainpipe"
end
Brainpipe.load!

pipe = Brainpipe.pipe(:data_transformer)

input = {
  order_ids: ["ORD-001", "ORD-001", "ORD-002", "ORD-002"],
  products: ["Widget", "Gadget", "Widget", "Gizmo"],
  quantities: [10, 5, 20, 3],
  prices: [25.0, 75.0, 25.0, 150.0]
}

puts "=== Data Transformer Example ==="
puts "Demonstrates: Explode, Link, and Collapse operations"
puts

puts "=== Input Data ==="
puts "Order IDs:  #{input[:order_ids].inspect}"
puts "Products:   #{input[:products].inspect}"
puts "Quantities: #{input[:quantities].inspect}"
puts "Prices:     #{input[:prices].inspect}"
puts

puts "=== Pipeline Stages ==="
puts "1. Explode:   Split arrays into individual items (1 namespace → 4 namespaces)"
puts "2. Link:      Enrich each item (copy product → product_name, set currency)"
puts "3. Collapse:  Aggregate all items (collect, sum, equal strategies)"
puts "4. Link:      Finalize output (move and delete fields)"
puts

result = pipe.call(**input)

puts "=== Output (Aggregated Summary) ==="
puts "Order IDs:      #{result[:unique_orders].inspect}"
puts "Unique Orders:  #{result[:unique_orders].uniq.inspect}"
puts "Products:       #{result[:product].inspect}"
puts "Total Quantity: #{result[:total_quantity]}"
puts "Prices:         #{result[:price].inspect}"
puts "Currency:       #{result[:currency]}"
puts

total_revenue = input[:quantities].zip(input[:prices]).sum { |q, p| q * p }
puts "=== Calculated Revenue ==="
puts "Line items: #{input[:quantities].zip(input[:prices]).map { |q, p| "#{q} × $#{p} = $#{q * p}" }.join(', ')}"
puts "Total:      $#{total_revenue}"
