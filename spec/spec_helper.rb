# frozen_string_literal: true

require "simplecov"
require "simplecov-console"

# Configure coverage formatters based on environment
SimpleCov.formatter = if ENV["COVERAGE"]
                        SimpleCov::Formatter::MultiFormatter.new([
                          SimpleCov::Formatter::HTMLFormatter,
                          SimpleCov::Formatter::Console,
                          SimpleCov::Formatter::SimpleFormatter,
                        ])
                      else
                        SimpleCov::Formatter::MultiFormatter.new([
                          SimpleCov::Formatter::HTMLFormatter,
                          SimpleCov::Formatter::Console,
                        ])
                      end

SimpleCov.start do
  add_filter "/spec/"
  add_filter "/vendor/"
  add_filter "/bin/"
  add_filter "/test/"
  add_filter "/coverage/"
  minimum_coverage 100
end

require "bundler/setup"
require "rails"
require "active_support"
require "active_record"
require "active_job"
require "attio"
require "attio/rails"
require "webmock/rspec"
require "pry"

# Load support files
Dir[File.join(File.dirname(__FILE__), "support", "**", "*.rb")].each { |f| require f }

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

  config.default_formatter = "doc" if config.files_to_run.one?

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  config.before(:each) do
    # Reset configuration to defaults before each test
    Attio::Rails.configuration = nil
    Attio::Rails.reset_client!
  end
end
