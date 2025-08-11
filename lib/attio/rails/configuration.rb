# frozen_string_literal: true

module Attio
  module Rails
    class Configuration
      attr_accessor :api_key, :default_workspace_id, :logger, :sync_enabled, :background_sync

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

        @client ||= ::Attio.client(api_key: configuration.api_key)
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
