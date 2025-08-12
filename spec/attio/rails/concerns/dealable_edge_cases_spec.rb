# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attio::Rails::Concerns::Dealable Edge Cases" do
  let(:deal_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"
      include Attio::Rails::Concerns::Dealable
      
      attio_pipeline_id "test_pipeline"
    end
  end

  let(:deal) { deal_class.new }
  let(:client) { instance_double(Attio::Client) }
  let(:deals_resource) { instance_double(Attio::Resources::Deals) }

  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(client).to receive(:respond_to?).with(:deals).and_return(true)
    allow(client).to receive(:deals).and_return(deals_resource)
    allow(Attio::Rails).to receive(:logger).and_return(Logger.new(nil))
  end

  describe "#deal_name edge cases" do
    context "with configuration" do
      it "uses configured name field" do
        deal_class.attio_deal_config do
          name_field :custom_name
        end
        
        deal.define_singleton_method(:custom_name) { "Custom Deal Name" }
        expect(deal.send(:deal_name)).to eq("Custom Deal Name")
      end
    end

    context "fallback chain" do
      it "falls back to name method when no config" do
        deal.name = "Standard Name"
        expect(deal.send(:deal_name)).to eq("Standard Name")
      end

      it "falls back to title when no name method" do
        deal.define_singleton_method(:title) { "Deal Title" }
        expect(deal.send(:deal_name)).to eq("Deal Title")
      end

      it "generates name from class and id when no other methods" do
        deal.id = 42
        expect(deal.send(:deal_name)).to match(/^.*#42$/)
      end
    end
  end

  describe "#deal_value edge cases" do
    context "with configuration" do
      it "uses configured value field" do
        deal_class.attio_deal_config do
          value_field :custom_amount
        end
        
        deal.define_singleton_method(:custom_amount) { 5000 }
        expect(deal.send(:deal_value)).to eq(5000)
      end
    end

    context "fallback chain" do
      it "falls back to value method when no config" do
        deal.value = 2500
        expect(deal.send(:deal_value)).to eq(2500)
      end

      it "falls back to amount when no value method" do
        deal.define_singleton_method(:amount) { 7500 }
        expect(deal.send(:deal_value)).to eq(7500)
      end

      it "returns 0 when no value methods available" do
        expect(deal.send(:deal_value)).to eq(0)
      end
    end
  end

  describe "#deal_progress edge cases" do
    it "calculates progress as percentage" do
      deal.define_singleton_method(:deal_value) { 250 }
      deal.define_singleton_method(:target_value) { 1000 }
      
      expect(deal.send(:deal_progress)).to eq(25.0)
    end

    it "returns 0 when target_value is nil" do
      deal.define_singleton_method(:deal_value) { 500 }
      deal.define_singleton_method(:target_value) { nil }
      
      expect(deal.send(:deal_progress)).to eq(0)
    end

    it "returns 0 when target_value is zero" do
      deal.define_singleton_method(:deal_value) { 500 }
      deal.define_singleton_method(:target_value) { 0 }
      
      expect(deal.send(:deal_progress)).to eq(0)
    end

    it "handles negative target values" do
      deal.define_singleton_method(:deal_value) { 500 }
      deal.define_singleton_method(:target_value) { -1000 }
      
      expect(deal.send(:deal_progress)).to eq(-50.0)
    end
  end

  describe "#sync_deal_to_attio_now edge cases" do
    context "when client doesn't support deals" do
      before do
        allow(client).to receive(:respond_to?).with(:deals).and_return(false)
      end

      it "returns nil and doesn't sync" do
        expect(deal.sync_deal_to_attio_now).to be_nil
      end
    end

    context "stage change handling" do
      before do
        deal.attio_deal_id = "existing_deal"
        allow(deals_resource).to receive(:update).and_return({ "data" => { "id" => "existing_deal" } })
      end

      it "handles stage change when configured" do
        deal_class.attio_deal_config do
          track_stage_changes true
          on_stage_change :stage_changed_callback
        end
        
        deal.define_singleton_method(:current_stage_id) { "stage1" }
        deal.define_singleton_method(:stage_id) { "stage2" }
        
        expect(deal).to receive(:stage_changed_callback)
        deal.sync_deal_to_attio_now
      end

      it "doesn't trigger callback when stages are same" do
        deal_class.attio_deal_config do
          track_stage_changes true
          on_stage_change :stage_callback
        end
        
        deal.define_singleton_method(:current_stage_id) { "stage1" }
        deal.define_singleton_method(:stage_id) { "stage1" }
        
        expect(deal).not_to receive(:stage_callback)
        deal.sync_deal_to_attio_now
      end
    end

    context "win/loss detection" do
      before do
        deal.attio_deal_id = "deal_123"
        allow(deals_resource).to receive(:update).and_return({ "data" => { "id" => "deal_123" } })
      end

      it "marks deal as won when is_won? returns true" do
        deal.define_singleton_method(:is_won?) { true }
        expect(deals_resource).to receive(:mark_won).with(id: "deal_123")
        
        deal.sync_deal_to_attio_now
      end

      it "marks deal as lost when is_lost? returns true" do
        deal.define_singleton_method(:is_lost?) { true }
        deal.define_singleton_method(:lost_reason) { "No budget" }
        
        expect(deals_resource).to receive(:mark_lost).with(
          id: "deal_123",
          lost_reason: "No budget"
        )
        
        deal.sync_deal_to_attio_now
      end

      it "doesn't mark as won/lost when methods return false" do
        deal.define_singleton_method(:is_won?) { false }
        deal.define_singleton_method(:is_lost?) { false }
        
        expect(deals_resource).not_to receive(:mark_won)
        expect(deals_resource).not_to receive(:mark_lost)
        
        deal.sync_deal_to_attio_now
      end
    end

    context "error handling" do
      it "calls error handler on sync failure" do
        error = StandardError.new("API Error")
        allow(deals_resource).to receive(:create).and_raise(error)
        
        error_handled = false
        deal_class.attio_deal_config do
          on_error ->(err) { error_handled = true if err.message == "API Error" }
        end
        
        deal.sync_deal_to_attio_now
        expect(error_handled).to be true
      end

      it "returns nil on error" do
        allow(deals_resource).to receive(:create).and_raise(StandardError)
        
        expect(deal.sync_deal_to_attio_now).to be_nil
      end
    end

    context "callbacks" do
      it "runs before_sync callback" do
        callback_run = false
        deal_class.attio_deal_config do
          before_sync { callback_run = true }
        end
        
        allow(deals_resource).to receive(:create).and_return({ "data" => { "id" => "new_deal" } })
        
        deal.sync_deal_to_attio_now
        expect(callback_run).to be true
      end

      it "runs after_sync callback with result" do
        result_captured = nil
        deal_class.attio_deal_config do
          after_sync ->(result) { result_captured = result }
        end
        
        response = { "data" => { "id" => "new_deal" } }
        allow(deals_resource).to receive(:create).and_return(response)
        
        deal.sync_deal_to_attio_now
        expect(result_captured).to eq(response)
      end

      it "runs on_create callback for new deals" do
        callback_run = false
        deal_class.attio_deal_config do
          on_create { callback_run = true }
        end
        
        allow(deals_resource).to receive(:create).and_return({ "data" => { "id" => "new_deal" } })
        
        deal.sync_deal_to_attio_now
        expect(callback_run).to be true
      end

      it "runs on_update callback for existing deals" do
        deal.attio_deal_id = "existing_deal"
        
        callback_run = false
        deal_class.attio_deal_config do
          on_update { callback_run = true }
        end
        
        allow(deals_resource).to receive(:update).and_return({ "data" => { "id" => "existing_deal" } })
        
        deal.sync_deal_to_attio_now
        expect(callback_run).to be true
      end
    end
  end

  describe "#remove_deal_from_attio edge cases" do
    context "when no attio_deal_id" do
      it "returns nil without making API call" do
        expect(deals_resource).not_to receive(:delete)
        expect(deal.remove_deal_from_attio).to be_nil
      end
    end

    context "when client doesn't support deals" do
      before do
        deal.attio_deal_id = "deal_123"
        allow(client).to receive(:respond_to?).with(:deals).and_return(false)
      end

      it "returns nil without deletion" do
        expect(deal.remove_deal_from_attio).to be_nil
      end
    end

    context "with callbacks" do
      before do
        deal.attio_deal_id = "deal_to_delete"
        allow(deals_resource).to receive(:delete).and_return({ success: true })
      end

      it "runs before_delete callback" do
        callback_run = false
        deal_class.attio_deal_config do
          before_delete { callback_run = true }
        end
        
        deal.remove_deal_from_attio
        expect(callback_run).to be true
      end

      it "runs after_delete callback" do
        callback_run = false
        deal_class.attio_deal_config do
          after_delete { callback_run = true }
        end
        
        deal.remove_deal_from_attio
        expect(callback_run).to be true
      end

      it "clears attio_deal_id after successful deletion" do
        deal.remove_deal_from_attio
        expect(deal.attio_deal_id).to be_nil
      end
    end

    context "error handling" do
      before do
        deal.attio_deal_id = "deal_123"
      end

      it "calls error handler on deletion failure" do
        error = StandardError.new("Delete failed")
        allow(deals_resource).to receive(:delete).and_raise(error)
        
        error_handled = false
        deal_class.attio_deal_config do
          on_error ->(err) { error_handled = true if err.message == "Delete failed" }
        end
        
        deal.remove_deal_from_attio
        expect(error_handled).to be true
      end

      it "returns nil on error" do
        allow(deals_resource).to receive(:delete).and_raise(StandardError)
        expect(deal.remove_deal_from_attio).to be_nil
      end

      it "doesn't clear attio_deal_id on error" do
        allow(deals_resource).to receive(:delete).and_raise(StandardError)
        deal.remove_deal_from_attio
        expect(deal.attio_deal_id).to eq("deal_123")
      end
    end
  end

  describe "class method configurations" do
    it "tracks won deals when configured" do
      deal_class.track_won_deals
      expect(deal_class.track_won_deals?).to be true
    end

    it "tracks lost deals when configured" do
      deal_class.track_lost_deals
      expect(deal_class.track_lost_deals?).to be true
    end

    it "sets attio_stage_field" do
      deal_class.attio_stage_field :custom_stage
      expect(deal_class.attio_stage_field).to eq(:custom_stage)
    end
  end
end