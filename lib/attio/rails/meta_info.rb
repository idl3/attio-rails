# frozen_string_literal: true

module Attio
  module Rails
    module MetaInfo
      extend self

      def workspace_info
        cache_fetch("attio:meta:workspace", expires_in: 1.hour) do
          client.meta.identify if client.respond_to?(:meta)
        end
      end

      def api_status
        cache_fetch("attio:meta:status", expires_in: 1.minute) do
          client.meta.status if client.respond_to?(:meta)
        end
      end

      def rate_limit_status
        client.meta.rate_limits if client.respond_to?(:meta)
      end

      def usage_statistics
        cache_fetch("attio:meta:usage", expires_in: 5.minutes) do
          client.meta.usage_stats if client.respond_to?(:meta)
        end
      end

      def feature_flags
        cache_fetch("attio:meta:features", expires_in: 1.hour) do
          client.meta.features if client.respond_to?(:meta)
        end
      end

      def available_endpoints
        cache_fetch("attio:meta:endpoints", expires_in: 24.hours) do
          client.meta.endpoints if client.respond_to?(:meta)
        end
      end

      def workspace_configuration
        cache_fetch("attio:meta:config", expires_in: 1.hour) do
          client.meta.workspace_config if client.respond_to?(:meta)
        end
      end

      def validate_api_key
        result = client.meta.validate_key if client.respond_to?(:meta)
        result && result[:valid] == true
      rescue StandardError => e
        Attio::Rails.logger.error("API key validation failed: #{e.message}")
        false
      end

      def healthy?
        status = api_status
        status && status[:status] == "operational"
      rescue StandardError => e
        Attio::Rails.logger.error("Health check failed: #{e.message}")
        false
      end

      def rate_limit_remaining
        status = rate_limit_status
        status[:remaining] if status
      rescue StandardError
        nil
      end

      def near_rate_limit?(threshold: 0.1)
        status = rate_limit_status
        return false unless status && status[:remaining] && status[:limit]

        remaining_ratio = status[:remaining].to_f / status[:limit]
        remaining_ratio <= threshold
      end

      def clear_meta_cache
        return unless defined?(::Rails.cache) && ::Rails.cache

        ::Rails.cache.delete_matched("attio:meta:*")
      end

      def register_health_check
        return unless defined?(::Rails.application.reloader)

        ::Rails.application.reloader.to_prepare do
          if defined?(::HealthCheck)
            ::HealthCheck.setup do |config|
              config.add_custom_check("attio") do
                Attio::Rails::MetaInfo.healthy? ? "" : "Attio API is not operational"
              end
            end
          end
        end
      end

      def log_usage_metrics
        stats = usage_statistics
        return unless stats

        Attio::Rails.logger.info("Attio Usage Metrics:")
        Attio::Rails.logger.info("  Records created: #{stats[:records_created]}")
        Attio::Rails.logger.info("  Records updated: #{stats[:records_updated]}")
        Attio::Rails.logger.info("  API calls today: #{stats[:api_calls_today]}")
        Attio::Rails.logger.info("  Storage used: #{stats[:storage_used_mb]} MB")
      end

      def check_feature(feature_name)
        flags = feature_flags
        return false unless flags

        flags[feature_name.to_sym] == true
      end

      def with_feature(feature_name)
        return unless check_feature(feature_name)

        yield
      end

      private def client
        @client ||= Attio::Rails.client
      end

      private def cache_fetch(key, ...)
        if defined?(::Rails.cache) && ::Rails.cache
          ::Rails.cache.fetch(key, ...)
        else
          yield
        end
      end
    end
  end
end
