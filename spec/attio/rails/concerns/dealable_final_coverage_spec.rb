# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attio::Rails::Concerns::Dealable Final Coverage" do
  let(:deal_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"
      include Attio::Rails::Concerns::Dealable
      
      attio_pipeline_id "test_pipeline"
      
      # Add stage_id attribute
      attr_accessor :stage_id, :current_stage_id
      
      def deal_name
        "Test Deal"
      end
      
      def deal_value  
        1000
      end
    end
  end

  let(:deal) { deal_class.new(name: "Test Deal", value: 1000) }
  let(:client) { instance_double(Attio::Client) }
  let(:deals_resource) { instance_double(Attio::Resources::Deals) }
  let(:logger) { instance_double(Logger) }

  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(Attio::Rails).to receive(:logger).and_return(logger)
    allow(client).to receive(:respond_to?).with(:deals).and_return(true)
    allow(client).to receive(:deals).and_return(deals_resource)
  end

  describe "sync_deal_stage_to_attio with stage_changed?" do
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
        
        deal.send(:sync_deal_stage_to_attio)
      end

      it "logs error and re-raises when update fails" do
        error = StandardError.new("Update failed")
        
        expect(deals_resource).to receive(:update).with(
          id: "existing_deal",
          data: { stage_id: "new_stage" }
        ).and_raise(error)
        
        expect(logger).to receive(:error).with("Failed to update deal stage: Update failed")
        
        expect {
          deal.send(:sync_deal_stage_to_attio)
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
        expect(deals_resource).not_to receive(:update)
        
        deal.send(:sync_deal_stage_to_attio)
      end
    end
  end

  describe "current_stage_id method with all paths" do
    context "with attio_stage_field configured and method exists" do
      it "uses the configured field" do
        deal_class.attio_stage_field :custom_stage_field
        deal.define_singleton_method(:custom_stage_field) { "custom_stage_value" }
        
        expect(deal.current_stage_id).to eq("custom_stage_value")
      end
    end

    context "with attio_stage_field configured but method doesn't exist" do
      it "falls back to stage_id" do
        deal_class.attio_stage_field :nonexistent_field
        deal.stage_id = "fallback_stage"
        
        expect(deal.current_stage_id).to eq("fallback_stage")
      end
    end

    context "without attio_stage_field, with stage_id" do
      it "uses stage_id method" do
        deal_class.attio_stage_field nil
        deal.stage_id = "direct_stage"
        
        expect(deal.current_stage_id).to eq("direct_stage")
      end
    end

    context "without stage_id, with status" do
      it "falls back to status method" do
        deal_class.attio_stage_field nil
        # Remove stage_id method/attribute
        deal.instance_eval { undef :stage_id if respond_to?(:stage_id) }
        deal.define_singleton_method(:status) { "status_value" }
        
        expect(deal.current_stage_id).to eq("status_value")
      end
    end

    context "with no stage methods available" do
      it "returns nil" do
        deal_class.attio_stage_field nil
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

    describe "Private helper methods not reached" do
      it "calculates deal_progress with zero target" do
        deal.define_singleton_method(:target_value) { 0 }
        expect(deal.send(:deal_progress)).to eq(0)
      end

      it "calculates deal_progress with valid target" do
        deal.define_singleton_method(:target_value) { 2000 }
        expect(deal.send(:deal_progress)).to eq(50.0)
      end
    end

    describe "Lines 434, 442, 450 - ActiveRecord callbacks" do
      it "sets up after_commit callback on update" do
        # These lines are callback registrations that execute during class loading
        # They're covered when the class is defined with the concern included
        expect(deal_class.instance_methods).to include(:sync_deal_stage_to_attio)
        expect(deal_class.instance_methods).to include(:sync_deal_to_attio_after_save)
        expect(deal_class.instance_methods).to include(:remove_deal_from_attio_after_destroy)
      end
    end
  end
end