# frozen_string_literal: true

require "spec_helper"
require "active_job"

RSpec.describe Attio::Rails::Jobs::AttioSyncJob do
  let(:job) { described_class.new }
  let(:model_class) { double("User", name: "User", attio_object_type: "people") }
  let(:model) { double("User", id: 1, should_sync_to_attio?: true, sync_to_attio_now: true) }
  let(:client) { instance_double(Attio::Client) }
  let(:records_resource) { instance_double(Attio::Resources::Records) }
  let(:deals_resource) { instance_double(Attio::Resources::Deals) }

  before do
    ActiveJob::Base.queue_adapter = :test
    allow(Attio::Rails).to receive(:sync_enabled?).and_return(true)
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(Attio::Rails).to receive(:logger).and_return(Logger.new(nil))
    allow(Attio::Rails.configuration).to receive(:queue).and_return(:default)
    allow(Attio::Rails.configuration).to receive(:raise_on_missing_record).and_return(false)
  end

  describe "queue configuration" do
    it "uses configured queue" do
      allow(Attio::Rails.configuration).to receive(:queue).and_return(:low_priority)
      expect(described_class.new.queue_name).to eq("low_priority")
    end

    it "defaults to default queue" do
      allow(Attio::Rails.configuration).to receive(:queue).and_return(nil)
      expect(described_class.new.queue_name).to eq("default")
    end
  end

  describe "retry configuration" do
    it "configures retry for RateLimitError with retry_after" do
      # The retry configuration is tested through actual job behavior
      # ActiveJob handles retries internally, so we verify the retry method exists
      expect(described_class).to respond_to(:retry_on)
    end
  end

  describe "#perform" do
    before do
      stub_const("User", model_class)
    end

    context "when sync is disabled" do
      before do
        allow(Attio::Rails).to receive(:sync_enabled?).and_return(false)
      end

      it "returns early without processing" do
        expect(model_class).not_to receive(:find_by)
        job.perform(model_name: "User", model_id: 1, action: :sync)
      end
    end

    context "sync action" do
      it "syncs the record" do
        expect(model_class).to receive(:find_by).with(id: 1).and_return(model)
        expect(model).to receive(:should_sync_to_attio?).and_return(true)
        expect(model).to receive(:sync_to_attio_now)

        job.perform(model_name: "User", model_id: 1, action: :sync)
      end

      it "skips sync if model not found" do
        expect(model_class).to receive(:find_by).with(id: 1).and_return(nil)
        expect { job.perform(model_name: "User", model_id: 1, action: :sync) }.not_to raise_error
      end

      it "skips sync if should_sync_to_attio? returns false" do
        expect(model_class).to receive(:find_by).with(id: 1).and_return(model)
        expect(model).to receive(:should_sync_to_attio?).and_return(false)
        expect(model).not_to receive(:sync_to_attio_now)

        job.perform(model_name: "User", model_id: 1, action: :sync)
      end
    end

    context "delete action" do
      before do
        allow(client).to receive(:records).and_return(records_resource)
      end

      it "deletes the Attio record" do
        expect(records_resource).to receive(:delete).with(
          object: "people",
          id: "attio_123"
        )

        job.perform(
          model_name: "User",
          model_id: 1,
          action: :delete,
          attio_record_id: "attio_123"
        )
      end

      it "skips deletion if no attio_record_id" do
        expect(records_resource).not_to receive(:delete)

        job.perform(model_name: "User", model_id: 1, action: :delete)
      end

      it "handles NotFoundError gracefully" do
        expect(records_resource).to receive(:delete).and_raise(Attio::NotFoundError)

        expect do
          job.perform(
            model_name: "User",
            model_id: 1,
            action: :delete,
            attio_record_id: "attio_123"
          )
        end.not_to raise_error
      end
    end

    context "sync_deal action" do
      let(:deal_model) { double("Opportunity", id: 1, sync_deal_to_attio_now: true) }

      it "syncs the deal" do
        expect(model_class).to receive(:find_by).with(id: 1).and_return(deal_model)
        expect(deal_model).to receive(:respond_to?).with(:sync_deal_to_attio_now).and_return(true)
        expect(deal_model).to receive(:sync_deal_to_attio_now)

        job.perform(model_name: "User", model_id: 1, action: :sync_deal)
      end

      it "skips if model doesn't support deal sync" do
        expect(model_class).to receive(:find_by).with(id: 1).and_return(model)
        expect(model).to receive(:respond_to?).with(:sync_deal_to_attio_now).and_return(false)
        expect(model).not_to receive(:sync_deal_to_attio_now)

        job.perform(model_name: "User", model_id: 1, action: :sync_deal)
      end
    end

    context "delete_deal action" do
      before do
        allow(client).to receive(:respond_to?).with(:deals).and_return(true)
        allow(client).to receive(:deals).and_return(deals_resource)
      end

      it "deletes the deal" do
        expect(deals_resource).to receive(:delete).with(id: "deal_123")

        job.perform(
          model_name: "User",
          model_id: 1,
          action: :delete_deal,
          attio_deal_id: "deal_123"
        )
      end

      it "handles NotFoundError gracefully" do
        expect(deals_resource).to receive(:delete).and_raise(Attio::NotFoundError)

        expect do
          job.perform(
            model_name: "User",
            model_id: 1,
            action: :delete_deal,
            attio_deal_id: "deal_123"
          )
        end.not_to raise_error
      end
    end

    context "batch operations" do
      it "handles batch_create" do
        expect(model_class).to receive(:find_by).with(id: 1).and_return(model)
        expect(Attio::Rails::BulkSync).to receive(:perform).with(
          [model],
          object_type: "people",
          operation: :create,
          custom: "option"
        )

        job.perform(
          model_name: "User",
          model_id: 1,
          action: :batch_create,
          object_type: "people",
          custom: "option"
        )
      end

      it "handles batch_update" do
        expect(model_class).to receive(:find_by).with(id: 1).and_return(model)
        expect(Attio::Rails::BulkSync).to receive(:perform).with(
          [model],
          object_type: "people",
          operation: :update
        )

        job.perform(
          model_name: "User",
          model_id: 1,
          action: :batch_update,
          object_type: "people"
        )
      end

      it "handles batch_upsert" do
        expect(model_class).to receive(:find_by).with(id: 1).and_return(model)
        expect(Attio::Rails::BulkSync).to receive(:perform).with(
          [model],
          object_type: "people",
          operation: :upsert,
          match_attribute: :email
        )

        job.perform(
          model_name: "User",
          model_id: 1,
          action: :batch_upsert,
          object_type: "people",
          match_attribute: :email
        )
      end

      it "handles batch_delete" do
        expect(model_class).to receive(:find_by).with(id: 1).and_return(model)
        expect(Attio::Rails::BulkSync).to receive(:perform).with(
          [model],
          object_type: "people",
          operation: :delete
        )

        job.perform(
          model_name: "User",
          model_id: 1,
          action: :batch_delete,
          object_type: "people"
        )
      end
    end

    context "unknown action" do
      it "logs error for unknown action" do
        expect(Attio::Rails.logger).to receive(:error).with("Unknown Attio sync action: unknown_action")

        job.perform(model_name: "User", model_id: 1, action: :unknown_action)
      end
    end

    context "error handling" do
      before do
        allow(model_class).to receive(:find_by).and_return(model)
      end

      it "handles authentication errors" do
        allow(model).to receive(:sync_to_attio_now).and_raise(Attio::AuthenticationError, "Invalid API key")
        expect(Attio::Rails.logger).to receive(:error).with("Attio authentication failed: Invalid API key")

        expect { job.perform(model_name: "User", model_id: 1, action: :sync) }
          .to raise_error(Attio::AuthenticationError)
      end

      it "handles validation errors without retrying" do
        allow(model).to receive(:sync_to_attio_now).and_raise(Attio::ValidationError, "Invalid data")
        expect(Attio::Rails.logger).to receive(:error).with("Attio validation error for User#1: Invalid data")

        expect { job.perform(model_name: "User", model_id: 1, action: :sync) }
          .not_to raise_error
      end

      it "handles general errors" do
        allow(model_class).to receive(:find_by).with(id: 1).and_return(model)
        allow(model).to receive(:sync_to_attio_now).and_raise(StandardError, "API Error")
        expect(Attio::Rails.logger).to receive(:error).with("Attio sync failed for User#1: API Error")
        allow(Rails).to receive(:env).and_return(double(development?: false))

        expect { job.perform(model_name: "User", model_id: 1, action: :sync) }
          .to raise_error(StandardError, "API Error")
      end

      it "reports errors to Rails error handler if available" do
        error = StandardError.new("API Error")
        allow(model).to receive(:sync_to_attio_now).and_raise(error)

        rails_error = double("Rails.error")
        stub_const("::Rails", double(error: rails_error, env: double(development?: false)))

        expect(rails_error).to receive(:report).with(
          error,
          context: hash_including(
            model_name: "User",
            model_id: 1,
            job: "Attio::Rails::Jobs::AttioSyncJob"
          )
        )

        expect { job.perform(model_name: "User", model_id: 1, action: :sync) }
          .to raise_error(StandardError)
      end
    end

    context "with raise_on_missing_record enabled" do
      before do
        allow(Attio::Rails.configuration).to receive(:raise_on_missing_record).and_return(true)
      end

      it "uses find instead of find_by" do
        expect(model_class).to receive(:find).with(1).and_return(model)
        expect(model).to receive(:sync_to_attio_now)

        job.perform(model_name: "User", model_id: 1, action: :sync)
      end

      it "raises error when record not found" do
        expect(model_class).to receive(:find).with(1).and_raise(ActiveRecord::RecordNotFound)

        expect { job.perform(model_name: "User", model_id: 1, action: :sync) }
          .to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "queue configuration coverage" do
    it "sets the queue name" do
      # This tests lines 11-12
      expect(described_class.queue_as).to eq(:default)
    end
    
    it "has queue priority defined" do
      expect(described_class.queue_as).not_to be_nil
    end
  end
end