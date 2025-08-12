# frozen_string_literal: true

require "attio"
require "rails"
require "active_support"
require "logger"

require "attio/rails/version"
require "attio/rails/configuration"
require "attio/rails/rate_limited_client"
require "attio/rails/bulk_sync"
require "attio/rails/workspace_manager"
require "attio/rails/meta_info"
require "attio/rails/concerns/syncable"
require "attio/rails/concerns/dealable"
require "attio/rails/jobs/attio_sync_job" if defined?(ActiveJob)
require "attio/rails/railtie"

module Attio
  module Rails
    class Error < StandardError; end
  end
end
