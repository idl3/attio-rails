# frozen_string_literal: true

require "spec_helper"

RSpec.describe Attio::Rails::MetaInfo do
  let(:client) { instance_double(Attio::Client) }
  let(:meta) { instance_double(Attio::Resources::Meta) }
  let(:cache) { double("cache") }

  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(Attio::Rails).to receive(:logger).and_return(Logger.new(nil))
    allow(described_class).to receive(:client).and_return(client)
  end

  describe ".workspace_info" do
    before do
      allow(client).to receive(:respond_to?).with(:meta).and_return(true)
      allow(client).to receive(:meta).and_return(meta)
    end

    context "with caching" do
      before do
        stub_const("::Rails", double(cache: cache))
      end

      it "caches workspace information" do
        workspace_data = { workspace_id: "ws_123", name: "Test Workspace" }
        allow(meta).to receive(:identify).and_return(workspace_data)

        expect(cache).to receive(:fetch).with("attio:meta:workspace", expires_in: 1.hour).and_yield

        result = described_class.workspace_info
        expect(result).to eq(workspace_data)
      end
    end

    context "without caching" do
      it "fetches directly" do
        workspace_data = { workspace_id: "ws_123", name: "Test Workspace" }
        expect(meta).to receive(:identify).and_return(workspace_data)

        result = described_class.workspace_info
        expect(result).to eq(workspace_data)
      end
    end
  end

  describe ".api_status" do
    before do
      allow(client).to receive(:respond_to?).with(:meta).and_return(true)
      allow(client).to receive(:meta).and_return(meta)
    end

    context "with caching" do
      before do
        stub_const("::Rails", double(cache: cache))
      end

      it "caches API status" do
        status_data = { status: "operational", version: "1.0" }
        allow(meta).to receive(:status).and_return(status_data)

        expect(cache).to receive(:fetch).with("attio:meta:status", expires_in: 1.minute).and_yield

        result = described_class.api_status
        expect(result).to eq(status_data)
      end
    end
  end

  describe ".rate_limit_status" do
    before do
      allow(client).to receive(:respond_to?).with(:meta).and_return(true)
      allow(client).to receive(:meta).and_return(meta)
    end

    it "returns current rate limit status without caching" do
      limits = { remaining: 900, limit: 1000, reset_at: Time.current + 3600 }
      expect(meta).to receive(:rate_limits).and_return(limits)

      result = described_class.rate_limit_status
      expect(result).to eq(limits)
    end
  end

  describe ".usage_statistics" do
    before do
      allow(client).to receive(:respond_to?).with(:meta).and_return(true)
      allow(client).to receive(:meta).and_return(meta)
    end

    context "with caching" do
      before do
        stub_const("::Rails", double(cache: cache))
      end

      it "caches usage statistics" do
        stats = { records_created: 100, api_calls_today: 500 }
        allow(meta).to receive(:usage_stats).and_return(stats)

        expect(cache).to receive(:fetch).with("attio:meta:usage", expires_in: 5.minutes).and_yield

        result = described_class.usage_statistics
        expect(result).to eq(stats)
      end
    end
  end

  describe ".feature_flags" do
    before do
      allow(client).to receive(:respond_to?).with(:meta).and_return(true)
      allow(client).to receive(:meta).and_return(meta)
    end

    context "with caching" do
      before do
        stub_const("::Rails", double(cache: cache))
      end

      it "caches feature flags" do
        features = { bulk_operations: true, advanced_search: false }
        allow(meta).to receive(:features).and_return(features)

        expect(cache).to receive(:fetch).with("attio:meta:features", expires_in: 1.hour).and_yield

        result = described_class.feature_flags
        expect(result).to eq(features)
      end
    end
  end

  describe ".available_endpoints" do
    before do
      allow(client).to receive(:respond_to?).with(:meta).and_return(true)
      allow(client).to receive(:meta).and_return(meta)
    end

    context "with caching" do
      before do
        stub_const("::Rails", double(cache: cache))
      end

      it "caches available endpoints" do
        endpoints = ["/records", "/lists", "/objects"]
        allow(meta).to receive(:endpoints).and_return(endpoints)

        expect(cache).to receive(:fetch).with("attio:meta:endpoints", expires_in: 24.hours).and_yield

        result = described_class.available_endpoints
        expect(result).to eq(endpoints)
      end
    end
  end

  describe ".workspace_configuration" do
    before do
      allow(client).to receive(:respond_to?).with(:meta).and_return(true)
      allow(client).to receive(:meta).and_return(meta)
    end

    context "with caching" do
      before do
        stub_const("::Rails", double(cache: cache))
      end

      it "caches workspace configuration" do
        config = { timezone: "UTC", date_format: "ISO" }
        allow(meta).to receive(:workspace_config).and_return(config)

        expect(cache).to receive(:fetch).with("attio:meta:config", expires_in: 1.hour).and_yield

        result = described_class.workspace_configuration
        expect(result).to eq(config)
      end
    end
  end

  describe ".validate_api_key" do
    before do
      allow(client).to receive(:respond_to?).with(:meta).and_return(true)
      allow(client).to receive(:meta).and_return(meta)
    end

    it "returns true for valid API key" do
      allow(meta).to receive(:validate_key).and_return({ valid: true })
      expect(described_class.validate_api_key).to be true
    end

    it "returns false for invalid API key" do
      allow(meta).to receive(:validate_key).and_return({ valid: false })
      expect(described_class.validate_api_key).to be false
    end

    it "returns false on error" do
      allow(meta).to receive(:validate_key).and_raise(StandardError, "Validation failed")
      expect(described_class.validate_api_key).to be false
    end
  end

  describe ".healthy?" do
    before do
      allow(client).to receive(:respond_to?).with(:meta).and_return(true)
      allow(client).to receive(:meta).and_return(meta)
    end

    it "returns true when API is operational" do
      allow(described_class).to receive(:api_status).and_return({ status: "operational" })
      expect(described_class.healthy?).to be true
    end

    it "returns false when API is not operational" do
      allow(described_class).to receive(:api_status).and_return({ status: "degraded" })
      expect(described_class.healthy?).to be false
    end

    it "returns false on error" do
      allow(described_class).to receive(:api_status).and_raise(StandardError)
      expect(described_class.healthy?).to be false
    end
  end

  describe ".rate_limit_remaining" do
    it "returns remaining requests" do
      allow(described_class).to receive(:rate_limit_status).and_return({ remaining: 900, limit: 1000 })
      expect(described_class.rate_limit_remaining).to eq(900)
    end

    it "returns nil on error" do
      allow(described_class).to receive(:rate_limit_status).and_raise(StandardError)
      expect(described_class.rate_limit_remaining).to be_nil
    end
  end

  describe ".near_rate_limit?" do
    it "returns true when near limit" do
      allow(described_class).to receive(:rate_limit_status).and_return({ remaining: 50, limit: 1000 })
      expect(described_class.near_rate_limit?(threshold: 0.1)).to be true
    end

    it "returns false when not near limit" do
      allow(described_class).to receive(:rate_limit_status).and_return({ remaining: 900, limit: 1000 })
      expect(described_class.near_rate_limit?(threshold: 0.1)).to be false
    end

    it "uses custom threshold" do
      allow(described_class).to receive(:rate_limit_status).and_return({ remaining: 200, limit: 1000 })
      expect(described_class.near_rate_limit?(threshold: 0.25)).to be true
      expect(described_class.near_rate_limit?(threshold: 0.15)).to be false
    end

    it "returns false on incomplete data" do
      allow(described_class).to receive(:rate_limit_status).and_return({ remaining: nil })
      expect(described_class.near_rate_limit?).to be false
    end
  end

  describe ".clear_meta_cache" do
    context "with Rails cache" do
      before do
        stub_const("::Rails", double(cache: cache))
      end

      it "clears all meta cache entries" do
        expect(cache).to receive(:delete_matched).with("attio:meta:*")
        described_class.clear_meta_cache
      end
    end

    context "without Rails cache" do
      it "does nothing" do
        expect { described_class.clear_meta_cache }.not_to raise_error
      end
    end
  end

  describe ".register_health_check" do
    context "with Rails application and HealthCheck gem" do
      let(:reloader) { double("reloader") }
      let(:health_check_config) { double("config") }

      before do
        stub_const("::Rails", double(application: double(reloader: reloader)))
        stub_const("::HealthCheck", double)
      end

      it "registers Attio health check" do
        expect(reloader).to receive(:to_prepare).and_yield
        expect(HealthCheck).to receive(:setup).and_yield(health_check_config)
        expect(health_check_config).to receive(:add_custom_check).with("attio")

        described_class.register_health_check
      end
    end

    context "without Rails application" do
      it "does nothing" do
        expect { described_class.register_health_check }.not_to raise_error
      end
    end
  end

  describe ".log_usage_metrics" do
    it "logs usage statistics" do
      stats = {
        records_created: 100,
        records_updated: 50,
        api_calls_today: 500,
        storage_used_mb: 25,
      }
      allow(described_class).to receive(:usage_statistics).and_return(stats)

      expect(Attio::Rails.logger).to receive(:info).with("Attio Usage Metrics:")
      expect(Attio::Rails.logger).to receive(:info).with("  Records created: 100")
      expect(Attio::Rails.logger).to receive(:info).with("  Records updated: 50")
      expect(Attio::Rails.logger).to receive(:info).with("  API calls today: 500")
      expect(Attio::Rails.logger).to receive(:info).with("  Storage used: 25 MB")

      described_class.log_usage_metrics
    end

    it "does nothing when no stats available" do
      allow(described_class).to receive(:usage_statistics).and_return(nil)
      expect(Attio::Rails.logger).not_to receive(:info)
      described_class.log_usage_metrics
    end
  end

  describe ".check_feature" do
    it "returns true for enabled features" do
      allow(described_class).to receive(:feature_flags).and_return({ bulk_operations: true, search: false })
      expect(described_class.check_feature(:bulk_operations)).to be true
    end

    it "returns false for disabled features" do
      allow(described_class).to receive(:feature_flags).and_return({ bulk_operations: true, search: false })
      expect(described_class.check_feature(:search)).to be false
    end

    it "returns false for unknown features" do
      allow(described_class).to receive(:feature_flags).and_return({ bulk_operations: true })
      expect(described_class.check_feature(:unknown)).to be false
    end

    it "returns false when feature flags unavailable" do
      allow(described_class).to receive(:feature_flags).and_return(nil)
      expect(described_class.check_feature(:any)).to be false
    end
  end

  describe ".with_feature" do
    it "yields when feature is enabled" do
      allow(described_class).to receive(:check_feature).with(:bulk_operations).and_return(true)

      result = nil
      described_class.with_feature(:bulk_operations) { result = "executed" }
      expect(result).to eq("executed")
    end

    it "does not yield when feature is disabled" do
      allow(described_class).to receive(:check_feature).with(:disabled_feature).and_return(false)

      result = nil
      described_class.with_feature(:disabled_feature) { result = "executed" }
      expect(result).to be_nil
    end
  end

  describe "error handling for complete coverage" do
    context "registration errors" do
      it "handles registration failures gracefully" do
        # This tests lines 92-93, 95
        allow(Rails).to receive(:application).and_raise(StandardError, "No Rails app")
        
        expect { described_class.register_health_check }.not_to raise_error
      end
      
      it "handles missing health check framework" do
        # This tests line 128
        allow(Rails).to receive(:application).and_return(double(config: double))
        allow(Rails.application.config).to receive(:respond_to?).with(:health_check).and_return(false)
        
        expect { described_class.register_health_check }.not_to raise_error
      end
    end
  end
end