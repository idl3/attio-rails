# frozen_string_literal: true

require "attio/rails/rspec/helpers"
require "attio/rails/rspec/matchers"

RSpec.configure do |config|
  config.include Attio::Rails::RSpec::Helpers, type: :model
  config.include Attio::Rails::RSpec::Matchers, type: :model
end
