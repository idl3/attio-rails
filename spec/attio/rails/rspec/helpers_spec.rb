# frozen_string_literal: true

require "attio/rails/rspec/helpers"

RSpec.describe Attio::Rails::RSpec::Helpers do
  include described_class

  before do
    Attio::Rails.configuration = nil
    Attio::Rails.configure { |c| c.api_key = "test_key" }
  end

  describe "#stub_attio_client" do
    it "returns stubbed client and records" do
      stubs = stub_attio_client

      expect(stubs[:client]).to be_an_instance_of(RSpec::Mocks::InstanceVerifyingDouble)
      expect(stubs[:records]).to be_an_instance_of(RSpec::Mocks::InstanceVerifyingDouble)
      expect(Attio::Rails.client).to eq(stubs[:client])
    end
  end

  describe "#stub_attio_create" do
    it "stubs create with default response" do
      stubs = stub_attio_create

      response = stubs[:records].create(object: "test", data: {})
      expect(response).to eq({ "data" => { "id" => "attio-test-id" } })
    end

    it "stubs create with custom response" do
      custom_response = { "data" => { "id" => "custom-id" } }
      stubs = stub_attio_create(custom_response)

      response = stubs[:records].create(object: "test", data: {})
      expect(response).to eq(custom_response)
    end
  end

  describe "#stub_attio_update" do
    it "stubs update with default response" do
      stubs = stub_attio_update

      response = stubs[:records].update(object: "test", id: "123", data: {})
      expect(response).to eq({ "data" => { "id" => "attio-test-id" } })
    end
  end

  describe "#stub_attio_delete" do
    it "stubs delete with default response" do
      stubs = stub_attio_delete

      response = stubs[:records].delete(object: "test", id: "123")
      expect(response).to eq({ "data" => { "deleted" => true } })
    end
  end

  describe "#expect_attio_sync" do
    it "sets expectation for create with specific attributes" do
      stubs = expect_attio_sync(object: "people", attributes: { name: "John" })

      stubs[:records].create(object: "people", data: { values: { name: "John" } })
    end

    it "yields to block if provided" do
      yielded = false
      stubs = expect_attio_sync(object: "people") { yielded = true }

      # Trigger the expected call
      stubs[:records].create(object: "people", data: { values: {} })

      expect(yielded).to be true
    end
  end

  describe "#expect_no_attio_sync" do
    it "sets expectation for no sync calls" do
      expect_no_attio_sync do
        # No sync should happen
      end
    end
  end

  describe "#with_attio_sync_disabled" do
    it "temporarily disables sync" do
      original_state = Attio::Rails.configuration.sync_enabled

      with_attio_sync_disabled do
        expect(Attio::Rails.configuration.sync_enabled).to be false
      end

      expect(Attio::Rails.configuration.sync_enabled).to eq(original_state)
    end
  end

  describe "#with_attio_background_sync" do
    it "temporarily enables background sync" do
      Attio::Rails.configure { |c| c.background_sync = false }

      with_attio_background_sync do
        expect(Attio::Rails.configuration.background_sync).to be true
      end

      expect(Attio::Rails.configuration.background_sync).to be false
    end
  end

  describe "#attio_sync_jobs" do
    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

    it "returns only AttioSyncJob jobs" do
      ActiveJob::Base.queue_adapter.enqueued_jobs << { job: AttioSyncJob, args: [] }
      ActiveJob::Base.queue_adapter.enqueued_jobs << { job: Object, args: [] }

      expect(attio_sync_jobs.size).to eq(1)
      expect(attio_sync_jobs.first[:job]).to eq(AttioSyncJob)
    end
  end

  describe "#clear_attio_sync_jobs" do
    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

    it "removes only AttioSyncJob jobs" do
      ActiveJob::Base.queue_adapter.enqueued_jobs << { job: AttioSyncJob, args: [] }
      ActiveJob::Base.queue_adapter.enqueued_jobs << { job: Object, args: [] }

      clear_attio_sync_jobs

      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.size).to eq(1)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.first[:job]).to eq(Object)
    end
  end
end
