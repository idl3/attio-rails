# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attio::Rails::Concerns::Dealable Final Coverage" do
  let(:deal_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"
      include Attio::Rails::Concerns::Dealable
      
      # Add stage_id attribute
      attr_accessor :stage_id, :current_stage_id, :attio_deal_id
      
      def deal_name
        "Test Deal"
      end
      
      def deal_value  
        1000
      end
    end.tap do |klass|
      klass.attio_pipeline_id = "test_pipeline"
    end
  end

  let(:deal) { deal_class.new }
  let(:client) { instance_double(Attio::Client) }
  let(:deals_resource) { instance_double(Attio::Resources::Deals) }
  let(:logger) { instance_double(Logger) }

  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(Attio::Rails).to receive(:logger).and_return(logger)
    allow(client).to receive(:respond_to?).with(:deals).and_return(true)
    allow(client).to receive(:deals).and_return(deals_resource)
  end

  describe "sync_deal_to_attio_now with stage_changed?" do
    before do
      deal.attio_deal_id = "existing_deal"
    end

    context "when stage has changed" do
      before do
        # Set up stage change detection
        deal.current_stage_id = "old_stage"
        deal.stage_id = "new_stage"
      end

      it "updates stage in Attio when stage_changed? is true" do
        expect(deals_resource).to receive(:update).with(
          id: "existing_deal",
          data: { stage_id: "new_stage" }
        ).and_return({ success: true })
        
        deal.sync_deal_to_attio_now
      end

      it "logs error and re-raises when update fails" do
        error = StandardError.new("Update failed")
        
        expect(deals_resource).to receive(:update).with(
          id: "existing_deal",
          data: { stage_id: "new_stage" }
        ).and_raise(error)
        
        expect(logger).to receive(:error).with("Failed to update deal stage: Update failed")
        
        expect {
          deal.sync_deal_to_attio_now
        }.to raise_error(StandardError, "Update failed")
      end
    end

    context "when stage has not changed" do
      before do
        # Same stage - no change
        deal.current_stage_id = "same_stage"
        deal.stage_id = "same_stage"
      end

      it "doesn't update when stages are the same" do
        # When stages haven't changed, it should do a regular update
        expect(deals_resource).to receive(:update).with(
          id: "existing_deal",
          data: deal.to_attio_deal
        ).and_return({ success: true })
        
        deal.sync_deal_to_attio_now
      end
    end
  end

  describe "current_stage_id method with all paths" do
    context "with attio_stage_field configured and method exists" do
      it "uses the configured field" do
        deal_class.attio_stage_field = :custom_stage_field
        deal.define_singleton_method(:custom_stage_field) { "custom_stage_value" }
        
        expect(deal.current_stage_id).to eq("custom_stage_value")
      end
    end

    context "with attio_stage_field configured but method doesn't exist" do
      it "falls back to stage_id" do
        deal_class.attio_stage_field = :nonexistent_field
        deal.stage_id = "fallback_stage"
        
        expect(deal.current_stage_id).to eq("fallback_stage")
      end
    end

    context "without attio_stage_field, with stage_id" do
      it "uses stage_id method" do
        deal_class.attio_stage_field = nil
        deal.stage_id = "direct_stage"
        
        expect(deal.current_stage_id).to eq("direct_stage")
      end
    end

    context "without stage_id, with status" do
      it "falls back to status method" do
        deal_class.attio_stage_field = nil
        # Remove stage_id method/attribute
        deal.instance_eval { undef :stage_id if respond_to?(:stage_id) }
        deal.define_singleton_method(:status) { "status_value" }
        
        expect(deal.current_stage_id).to eq("status_value")
      end
    end

    context "with no stage methods available" do
      it "returns nil" do
        deal_class.attio_stage_field = nil
        # Remove all stage methods
        deal.instance_eval { undef :stage_id if respond_to?(:stage_id) }
        
        expect(deal.current_stage_id).to be_nil
      end
    end
  end

  describe "Additional uncovered scenarios" do
    describe "run_deal_callback with Symbol type" do
      it "calls method specified by symbol callback" do
        deal_class.attio_deal_config do
          callbacks[:test_callback] = :symbol_callback_method
        end
        
        callback_executed = false
        deal.define_singleton_method(:symbol_callback_method) do |*args|
          callback_executed = true
        end
        
        deal.send(:run_deal_callback, :test_callback)
        expect(callback_executed).to be true
      end
    end

    describe "Private helper methods" do
      it "handles run_deal_callback with no callback defined" do
        # This test ensures the branch where callback is nil is covered
        expect { deal.send(:run_deal_callback, :nonexistent_callback) }.not_to raise_error
      end
    end
  end
end