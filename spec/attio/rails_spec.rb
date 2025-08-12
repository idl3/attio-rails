# frozen_string_literal: true

RSpec.describe Attio::Rails do
  it "has a version number" do
    expect(Attio::Rails::VERSION).not_to be nil
  end

  describe ".configuration" do
    it "returns a configuration instance" do
      expect(described_class.configuration).to be_a(Attio::Rails::Configuration)
    end

    it "memoizes the configuration" do
      config1 = described_class.configuration
      config2 = described_class.configuration
      expect(config1).to be(config2)
    end
  end

  describe ".configure" do
    it "yields the configuration" do
      expect { |b| described_class.configure(&b) }.to yield_with_args(Attio::Rails::Configuration)
    end

    it "resets the client after configuration" do
      described_class.configure { |c| c.api_key = "old_key" }
      client1 = described_class.client

      described_class.configure { |c| c.api_key = "new_key" }
      client2 = described_class.client

      expect(client1).not_to be(client2)
    end
  end

  describe ".client" do
    context "when API key is configured" do
      before do
        described_class.configure { |c| c.api_key = "test_key" }
      end

      it "returns an Attio client" do
        client = described_class.client
        expect(client).to(satisfy { |c| c.is_a?(Attio::Client) || c.is_a?(Attio::Rails::RateLimitedClient) })
      end

      it "memoizes the client" do
        client1 = described_class.client
        client2 = described_class.client
        expect(client1).to be(client2)
      end
    end

    context "when API key is not configured" do
      before do
        described_class.configure { |c| c.api_key = nil }
      end

      it "raises a configuration error" do
        expect do
          described_class.client
        end.to raise_error(Attio::Rails::ConfigurationError, "Attio API key not configured")
      end
    end
  end

  describe ".reset_client!" do
    it "clears the memoized client" do
      described_class.configure { |c| c.api_key = "test_key" }
      client1 = described_class.client
      described_class.reset_client!
      client2 = described_class.client

      expect(client1).not_to be(client2)
    end
  end

  describe ".sync_enabled?" do
    it "returns true by default" do
      # Ensure we have a fresh configuration
      described_class.configuration = nil
      expect(described_class.sync_enabled?).to be true
    end

    it "returns the configured value" do
      described_class.configure { |c| c.sync_enabled = false }
      expect(described_class.sync_enabled?).to be false
    end
  end

  describe ".background_sync?" do
    it "returns true by default" do
      # Ensure we have a fresh configuration
      described_class.configuration = nil
      expect(described_class.background_sync?).to be true
    end

    it "returns the configured value" do
      described_class.configure { |c| c.background_sync = false }
      expect(described_class.background_sync?).to be false
    end
  end

  describe ".logger" do
    it "returns a logger" do
      expect(described_class.logger).to respond_to(:info)
      expect(described_class.logger).to respond_to(:error)
    end
  end
end
