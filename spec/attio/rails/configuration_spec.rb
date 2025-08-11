# frozen_string_literal: true

RSpec.describe Attio::Rails::Configuration do
  let(:configuration) { described_class.new }

  describe "#initialize" do
    it "sets api_key from environment variable" do
      allow(ENV).to receive(:fetch).with("ATTIO_API_KEY", nil).and_return("env_key")
      config = described_class.new
      expect(config.api_key).to eq("env_key")
    end

    it "sets default_workspace_id to nil" do
      expect(configuration.default_workspace_id).to be_nil
    end

    it "sets sync_enabled to true by default" do
      expect(configuration.sync_enabled).to be true
    end

    it "sets background_sync to true by default" do
      expect(configuration.background_sync).to be true
    end

    it "sets a logger" do
      expect(configuration.logger).to be_a(Logger)
    end

    context "when Rails is defined" do
      let(:rails_logger) { instance_double(Logger) }

      before do
        stub_const("Rails", double(logger: rails_logger))
      end

      it "uses Rails.logger" do
        expect(described_class.new.logger).to eq(rails_logger)
      end
    end
  end

  describe "#valid?" do
    it "returns true when api_key is present" do
      configuration.api_key = "valid_key"
      expect(configuration.valid?).to be true
    end

    it "returns false when api_key is nil" do
      configuration.api_key = nil
      expect(configuration.valid?).to be false
    end

    it "returns false when api_key is empty" do
      configuration.api_key = ""
      expect(configuration.valid?).to be false
    end
  end

  describe "accessors" do
    it "allows setting and getting api_key" do
      configuration.api_key = "new_key"
      expect(configuration.api_key).to eq("new_key")
    end

    it "allows setting and getting default_workspace_id" do
      configuration.default_workspace_id = "workspace123"
      expect(configuration.default_workspace_id).to eq("workspace123")
    end

    it "allows setting and getting logger" do
      new_logger = Logger.new(nil)
      configuration.logger = new_logger
      expect(configuration.logger).to eq(new_logger)
    end

    it "allows setting and getting sync_enabled" do
      configuration.sync_enabled = false
      expect(configuration.sync_enabled).to be false
    end

    it "allows setting and getting background_sync" do
      configuration.background_sync = false
      expect(configuration.background_sync).to be false
    end
  end
end
