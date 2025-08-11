module Attio
  module Rails
    class Configuration
      attr_accessor :api_key, :default_workspace_id, :logger, :sync_enabled, :background_sync

      def initialize
        @api_key = ENV['ATTIO_API_KEY']
        @default_workspace_id = nil
        @logger = defined?(::Rails) ? ::Rails.logger : Logger.new(STDOUT)
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