# frozen_string_literal: true

module Attio
  module Rails
    class Configuration
      attr_accessor :api_key, :default_workspace_id, :logger, :sync_enabled, :background_sync,
                    :queue, :raise_on_missing_record, :max_requests_per_hour, :max_retries,
                    :bulk_batch_size, :upsert_match_attribute, :enable_rate_limiting

      def initialize
        @api_key = ENV.fetch("ATTIO_API_KEY", nil)
        @default_workspace_id = nil
        @logger = if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
                    ::Rails.logger
                  else
                    ::Logger.new($stdout)
                  end
        @sync_enabled = true
        @background_sync = true
        @queue = :default
        @raise_on_missing_record = false
        @max_requests_per_hour = 1000
        @max_retries = 3
        @bulk_batch_size = 100
        @upsert_match_attribute = :email
        @enable_rate_limiting = true
      end

      def valid?
        !api_key.nil? && !api_key.empty?
      end
    end

    class << self
      attr_writer :configuration

      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
        reset_client!
      end

      def client
        raise ConfigurationError, "Attio API key not configured" unless configuration.valid?

        @client ||= if configuration.enable_rate_limiting
                      RateLimitedClient.new(config: configuration)
                    else
                      ::Attio.client(api_key: configuration.api_key)
                    end
      end

      def reset_client!
        @client = nil
      end

      def sync_enabled?
        configuration.sync_enabled
      end

      def background_sync?
        configuration.background_sync
      end

      def logger
        configuration.logger
      end
    end

    class ConfigurationError < StandardError; end
  end
end
