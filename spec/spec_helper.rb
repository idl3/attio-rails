if ENV['COVERAGE'] || ENV['CI']
  require 'simplecov'
  require 'simplecov-cobertura' if ENV['CI']
  
  formatters = [SimpleCov::Formatter::HTMLFormatter]
  
  if ENV['CI']
    formatters << SimpleCov::Formatter::CoberturaFormatter
  else
    require 'simplecov-console'
    formatters << SimpleCov::Formatter::Console
  end
  
  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(formatters)
  
  SimpleCov.start do
    add_filter '/spec/'
    add_filter '/vendor/'
    add_filter '/test/'
    minimum_coverage ENV['CI'] ? 85 : 100
  end
end

require 'bundler/setup'
require 'rails'
require 'active_support'
require 'active_record'
require 'active_job'
require 'attio'
require 'attio/rails'
require 'webmock/rspec'
require 'pry'

# Load support files
Dir[File.join(File.dirname(__FILE__), 'support', '**', '*.rb')].each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  if config.files_to_run.one?
    config.default_formatter = "doc"
  end

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  config.before(:each) do
    Attio::Rails.reset_client!
  end
end