#!/usr/bin/env ruby

# Test without loading external dependencies
$LOAD_PATH.unshift(File.expand_path('../lib', __FILE__))
$LOAD_PATH.unshift(File.expand_path('../../attio/lib', __FILE__))

puts "Testing Attio Rails gem structure..."

# Test version file
require 'attio/rails/version'
puts "✓ Version loaded: #{Attio::Rails::VERSION}"

# Test that all files exist
files_to_check = [
  'lib/attio/rails.rb',
  'lib/attio/rails/configuration.rb',
  'lib/attio/rails/concerns/syncable.rb',
  'lib/attio/rails/railtie.rb',
  'lib/generators/attio/install/install_generator.rb',
  'lib/generators/attio/install/templates/attio.rb',
  'lib/generators/attio/install/templates/attio_sync_job.rb',
  'lib/generators/attio/install/templates/migration.rb',
  'lib/generators/attio/install/templates/README.md'
]

files_to_check.each do |file|
  if File.exist?(file)
    puts "✓ #{file} exists"
  else
    puts "✗ #{file} is missing!"
  end
end

# Test spec files exist
spec_files = Dir.glob('spec/**/*_spec.rb')
puts "\nFound #{spec_files.length} spec files:"
spec_files.each { |f| puts "  - #{f}" }

puts "\nBasic structure test completed!"