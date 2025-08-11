# frozen_string_literal: true

require "attio"
require "rails"
require "active_support"
require "logger"

require "attio/rails/version"
require "attio/rails/configuration"
require "attio/rails/concerns/syncable"
require "attio/rails/railtie"

module Attio
  module Rails
    class Error < StandardError; end
  end
end
