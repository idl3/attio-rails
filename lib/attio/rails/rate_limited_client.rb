# frozen_string_literal: true

module Attio
  module Rails
    class RateLimitedClient
      attr_reader :client, :rate_limiter

      def initialize(api_key: nil, workspace_id: nil, config: Attio::Rails.configuration)
        @config = config
        @api_key = api_key || config.api_key
        @workspace_id = workspace_id || config.default_workspace_id
        @client = build_client
        @rate_limiter = build_rate_limiter
        @logger = config.logger || ::Rails.logger
      end

      def method_missing(method_name, ...)
        if @client.respond_to?(method_name)
          with_rate_limiting { @client.send(method_name, ...) }
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @client.respond_to?(method_name, include_private) || super
      end

      def with_rate_limiting(&block)
        retries = 0
        begin
          @rate_limiter.execute(&block)
        rescue Attio::RateLimitError => e
          raise e unless retries < 3 && !(@config.background_sync && defined?(AttioSyncJob))

          retries += 1
          retry_after = e.retry_after || 60
          @logger.warn("Rate limit exceeded. Retrying after #{retry_after} seconds (attempt #{retries}/3)")
          sleep(retry_after)
          retry
        end
      end

      def rate_limit_status
        {
          remaining_requests: @rate_limiter.remaining_requests,
          reset_time: @rate_limiter.reset_time,
          current_usage: @rate_limiter.current_usage,
          max_requests: @rate_limiter.max_requests,
        }
      end

      def healthy?
        response = @client.meta.status
        response[:status] == "operational"
      rescue StandardError => e
        @logger.error("Attio health check failed: #{e.message}")
        false
      end

      private def build_client
        Attio::Client.new(api_key: @api_key)
      end

      private def build_rate_limiter
        Attio::RateLimiter.new(
          max_requests: @config.max_requests_per_hour || 1000,
          window_seconds: 3600,
          max_retries: @config.max_retries || 3,
          enable_jitter: true
        )
      end
    end
  end
end
