# frozen_string_literal: true

require "spec_helper"

RSpec.describe Attio::Rails::Concerns::Dealable do
  let(:deal_class) do
    # Create a fresh class for each test to avoid state leakage
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"
      include Attio::Rails::Concerns::Dealable
      
      attr_accessor :attio_deal_id, :value, :stage_id, :status, :closed_date, :lost_reason, :current_stage_id,
                    :company_attio_id, :owner_attio_id, :expected_close_date
      
      def initialize(attrs = {})
        super(attrs.except(:value, :stage_id, :attio_deal_id, :status, :closed_date, :lost_reason, :current_stage_id,
                          :company_attio_id, :owner_attio_id, :expected_close_date))
        @value = attrs[:value]
        @stage_id = attrs[:stage_id]
        @attio_deal_id = attrs[:attio_deal_id]
        @status = attrs[:status]
        @closed_date = attrs[:closed_date]
        @lost_reason = attrs[:lost_reason]
        @current_stage_id = attrs[:current_stage_id]
        @company_attio_id = attrs[:company_attio_id]
        @owner_attio_id = attrs[:owner_attio_id]
        @expected_close_date = attrs[:expected_close_date]
      end
      
      def id
        @id ||= rand(1000)
      end
      
      def update_column(column, value)
        send("#{column}=", value)
      end
    end
    # Give the class a name so self.class.name returns "Opportunity"
    stub_const("Opportunity", klass)
    klass
  end

  let(:deal) { deal_class.new(name: "Big Deal", value: 10_000, stage_id: "stage_1") }
  let(:client) { double("Attio::Client") }
  let(:deals_resource) { double("Attio::Resources::Deals") }

  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(Attio::Rails).to receive(:sync_enabled?).and_return(true)
    allow(Attio::Rails).to receive(:background_sync?).and_return(false)
    allow(Attio::Rails).to receive(:logger).and_return(Logger.new(nil))
  end

  describe ".attio_deal_config" do
    it "configures deal settings with a block" do
      deal_class.attio_deal_config do
        pipeline_id "sales_pipeline"
        name_field :title
        value_field :amount
        stage_field :current_stage
      end

      config = deal_class.attio_deal_config
      expect(config.pipeline_id).to eq("sales_pipeline")
      expect(config.name_field).to eq(:title)
      expect(config.value_field).to eq(:amount)
      expect(config.stage_field).to eq(:current_stage)
    end

    it "sets pipeline_id directly" do
      deal_class.attio_deal_config(pipeline_id: "direct_pipeline")
      expect(deal_class.attio_pipeline_id).to eq("direct_pipeline")
    end
  end

  describe ".sync_all_deals_to_attio" do
    it "performs bulk sync for all deals" do
      deals = [deal]
      allow(deal_class).to receive(:all).and_return(deals)

      expect(Attio::Rails::BulkSync).to receive(:perform).with(
        deals,
        object_type: "deals",
        transform: :to_attio_deal,
        custom: "option"
      )

      deal_class.sync_all_deals_to_attio(custom: "option")
    end
  end

  describe "#sync_deal_to_attio" do
    before do
      deal_class.attio_deal_config(pipeline_id: "test_pipeline")
      allow(client).to receive(:respond_to?).with(:deals).and_return(true)
      allow(client).to receive(:deals).and_return(deals_resource)
    end

    context "with background sync disabled" do
      it "syncs immediately" do
        expect(deal).to receive(:sync_deal_to_attio_now)
        deal.sync_deal_to_attio
      end
    end

    context "with background sync enabled" do
      before do
        allow(Attio::Rails).to receive(:background_sync?).and_return(true)
        stub_const("AttioSyncJob", Class.new do
          def self.perform_later(*args)
            # Stub implementation
          end
        end)
      end

      it "enqueues a background job" do
        expect(AttioSyncJob).to receive(:perform_later).with(
          model_name: "Opportunity",
          model_id: deal.id,
          action: :sync_deal
        )
        deal.sync_deal_to_attio
      end
    end

    it "runs before_sync callback" do
      callback_run = false
      deal_class.attio_deal_config do
        pipeline_id "test_pipeline"
        before_sync { callback_run = true }
      end

      allow(deals_resource).to receive(:create).and_return({ id: "deal_123" })
      deal.sync_deal_to_attio
      expect(callback_run).to be true
    end

    it "handles errors with custom error handler" do
      error_handled = false
      deal_class.attio_deal_config do
        pipeline_id "test_pipeline"
        on_error ->(_e) { error_handled = true }
      end

      allow(deals_resource).to receive(:create).and_raise(StandardError, "API Error")
      deal.sync_deal_to_attio
      expect(error_handled).to be true
    end
  end

  describe "#sync_deal_to_attio_now" do
    before do
      deal_class.attio_deal_config(pipeline_id: "test_pipeline")
      allow(client).to receive(:respond_to?).with(:deals).and_return(true)
      allow(client).to receive(:deals).and_return(deals_resource)
    end

    context "when creating a new deal" do
      it "creates the deal in Attio" do
        expect(deals_resource).to receive(:create).with(
          data: hash_including(
            name: "Big Deal",
            value: 10_000,
            pipeline_id: "test_pipeline"
          )
        ).and_return({ id: "new_deal_id" })

        expect(deal).to receive(:update_column).with(:attio_deal_id, "new_deal_id")

        result = deal.sync_deal_to_attio_now
        expect(result[:id]).to eq("new_deal_id")
      end
    end

    context "when updating existing deal" do
      before do
        deal.attio_deal_id = "existing_deal_id"
      end

      it "updates the deal in Attio" do
        expect(deals_resource).to receive(:update).with(
          id: "existing_deal_id",
          data: hash_including(
            name: "Big Deal",
            value: 10_000,
            pipeline_id: "test_pipeline"
          )
        ).and_return({ id: "existing_deal_id", updated: true })

        result = deal.sync_deal_to_attio_now
        expect(result[:updated]).to be true
      end
    end

    it "runs after_sync callback" do
      callback_result = nil
      deal_class.attio_deal_config do
        pipeline_id "test_pipeline"
        after_sync ->(result) { callback_result = result }
      end

      allow(deals_resource).to receive(:create).and_return({ id: "deal_123" })
      deal.sync_deal_to_attio_now
      expect(callback_result[:id]).to eq("deal_123")
    end
  end

  describe "#remove_deal_from_attio" do
    before do
      deal.attio_deal_id = "deal_to_remove"
      allow(client).to receive(:respond_to?).with(:deals).and_return(true)
      allow(client).to receive(:deals).and_return(deals_resource)
    end

    context "with background sync disabled" do
      it "removes immediately" do
        expect(deals_resource).to receive(:delete).with(id: "deal_to_remove")
        deal.remove_deal_from_attio_now
      end
    end

    context "with background sync enabled" do
      before do
        allow(Attio::Rails).to receive(:background_sync?).and_return(true)
        stub_const("AttioSyncJob", Class.new do
          def self.perform_later(*args)
            # Stub implementation
          end
        end)
      end

      it "enqueues a background job" do
        expect(AttioSyncJob).to receive(:perform_later).with(
          model_name: "Opportunity",
          model_id: deal.id,
          action: :delete_deal,
          attio_deal_id: "deal_to_remove"
        )
        deal.remove_deal_from_attio
      end
    end

    it "does nothing if no attio_deal_id" do
      deal.attio_deal_id = nil
      expect(deals_resource).not_to receive(:delete)
      deal.remove_deal_from_attio_now
    end
  end

  describe "#mark_as_won!" do
    before do
      deal_class.track_won_deals
      deal.attio_deal_id = "winning_deal"
      allow(client).to receive(:respond_to?).with(:deals).and_return(true)
      allow(client).to receive(:deals).and_return(deals_resource)
      allow(deal).to receive(:update!)
    end

    it "updates local status and syncs to Attio" do
      won_date = Time.current
      expect(deal).to receive(:update!).with(status: "won", closed_date: won_date)
      expect(deals_resource).to receive(:mark_won).with(
        id: "winning_deal",
        won_date: won_date,
        actual_value: 10_000
      )

      deal.mark_as_won!(won_date: won_date)
    end

    it "uses provided actual value" do
      won_date = Time.current
      allow(deal).to receive(:update!)
      expect(deals_resource).to receive(:mark_won).with(
        id: "winning_deal",
        won_date: won_date,
        actual_value: 12_000
      )

      deal.mark_as_won!(won_date: won_date, actual_value: 12_000)
    end

    it "runs on_won callback" do
      callback_run = false
      deal_class.attio_deal_config do
        on_won { callback_run = true }
      end

      allow(deal).to receive(:update!)
      allow(deals_resource).to receive(:mark_won)

      deal.mark_as_won!
      expect(callback_run).to be true
    end
  end

  describe "#mark_as_lost!" do
    before do
      deal_class.track_lost_deals
      deal.attio_deal_id = "losing_deal"
      allow(client).to receive(:respond_to?).with(:deals).and_return(true)
      allow(client).to receive(:deals).and_return(deals_resource)
      allow(deal).to receive(:update!)
    end

    it "updates local status and syncs to Attio" do
      lost_date = Time.current
      expect(deal).to receive(:update!).with(
        status: "lost",
        closed_date: lost_date,
        lost_reason: "Competition"
      )
      expect(deals_resource).to receive(:mark_lost).with(
        id: "losing_deal",
        lost_reason: "Competition",
        lost_date: lost_date
      )

      deal.mark_as_lost!(lost_reason: "Competition", lost_date: lost_date)
    end

    it "runs on_lost callback" do
      callback_run = false
      deal_class.attio_deal_config do
        on_lost { callback_run = true }
      end

      allow(deal).to receive(:update!)
      allow(deals_resource).to receive(:mark_lost)

      deal.mark_as_lost!
      expect(callback_run).to be true
    end
  end

  describe "#update_stage!" do
    before do
      deal.attio_deal_id = "staged_deal"
      allow(client).to receive(:respond_to?).with(:deals).and_return(true)
      allow(client).to receive(:deals).and_return(deals_resource)
      allow(deal).to receive(:update!)
    end

    it "updates local stage and syncs to Attio" do
      new_stage = "stage_2"
      expect(deal).to receive(:update!).with(current_stage_id: new_stage)
      expect(deals_resource).to receive(:update_stage).with(
        id: "staged_deal",
        stage_id: new_stage
      )

      deal.update_stage!(new_stage)
    end

    it "runs on_stage_change callback" do
      callback_stage = nil
      deal_class.attio_deal_config do
        on_stage_change ->(stage) { callback_stage = stage }
      end

      allow(deal).to receive(:update!)
      allow(deals_resource).to receive(:update_stage)

      deal.update_stage!("stage_3")
      expect(callback_stage).to eq("stage_3")
    end
  end

  describe "#to_attio_deal" do
    before do
      deal_class.attio_deal_config(pipeline_id: "test_pipeline")
    end

    it "returns deal data hash" do
      data = deal.to_attio_deal
      expect(data).to include(
        name: "Big Deal",
        value: 10_000,
        pipeline_id: "test_pipeline",
        stage_id: "stage_1"
      )
    end

    it "includes optional fields when available" do
      allow(deal).to receive(:company_attio_id).and_return("company_123")
      allow(deal).to receive(:owner_attio_id).and_return("owner_456")
      allow(deal).to receive(:expected_close_date).and_return(Date.today)

      data = deal.to_attio_deal
      expect(data).to include(
        company_id: "company_123",
        owner_id: "owner_456",
        expected_close_date: Date.today
      )
    end

    it "applies transform when configured" do
      deal_class.attio_deal_config do
        pipeline_id "test_pipeline"
        transform ->(data, _deal) { data.merge(custom_field: "custom_value") }
      end

      data = deal.to_attio_deal
      expect(data[:custom_field]).to eq("custom_value")
    end
  end

  describe "#should_sync_deal?" do
    before do
      deal_class.attio_deal_config(pipeline_id: "test_pipeline")
    end

    it "returns true when sync is enabled and pipeline is configured" do
      expect(deal.should_sync_deal?).to be true
    end

    it "returns false when sync is disabled" do
      allow(Attio::Rails).to receive(:sync_enabled?).and_return(false)
      expect(deal.should_sync_deal?).to be false
    end

    it "returns false when no pipeline is configured" do
      # Explicitly ensure no pipeline_id is set
      deal_class.class_eval do
        self._attio_pipeline_id = nil
        self.attio_deal_configuration = nil
      end
      expect(deal.should_sync_deal?).to be false
    end

    it "respects sync_if condition" do
      deal_class.attio_deal_config do
        pipeline_id "test_pipeline"
        sync_if ->(deal) { deal.value > 5000 }
      end

      expect(deal.should_sync_deal?).to be true

      deal.value = 1000
      expect(deal.should_sync_deal?).to be false
    end
  end

  describe "#should_remove_deal?" do
    it "returns true when deal has attio_id and sync is enabled" do
      deal.attio_deal_id = "deal_123"
      expect(deal.should_remove_deal?).to be true
    end

    it "returns false when deal has no attio_id" do
      deal.attio_deal_id = nil
      expect(deal.should_remove_deal?).to be false
    end

    it "returns false when sync is disabled" do
      deal.attio_deal_id = "deal_123"
      allow(Attio::Rails).to receive(:sync_enabled?).and_return(false)
      expect(deal.should_remove_deal?).to be false
    end
  end

end