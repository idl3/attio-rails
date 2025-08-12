# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attio::Rails::Concerns::Dealable After Commit Hooks" do
  let(:deal_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"
      include Attio::Rails::Concerns::Dealable
      
      attio_pipeline_id "test_pipeline"
      attio_stage_field :stage_id
      
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
    
    # Set up the deal as if it's already synced
    deal.attio_deal_id = "existing_deal_123"
  end

  describe "after_commit :sync_deal_stage_to_attio" do
    context "when stage_id changes" do
      it "updates stage in Attio successfully" do
        deal.stage_id = "new_stage"
        
        expect(deals_resource).to receive(:update).with(
          id: "existing_deal_123",
          data: { stage_id: "new_stage" }
        )
        
        # Simulate after_commit callback
        deal.send(:sync_deal_stage_to_attio)
      end

      it "logs and re-raises error on failure" do
        deal.stage_id = "new_stage"
        error = StandardError.new("API error")
        
        expect(deals_resource).to receive(:update).and_raise(error)
        expect(logger).to receive(:error).with("Failed to update deal stage: API error")
        
        expect {
          deal.send(:sync_deal_stage_to_attio)
        }.to raise_error(StandardError, "API error")
      end
    end

    context "when status changes to won" do
      before do
        deal.define_singleton_method(:status) { "won" }
        deal.define_singleton_method(:closed_date) { Date.today }
      end

      it "marks deal as won in Attio" do
        expect(deals_resource).to receive(:update).with(
          id: "existing_deal_123",
          data: { status: "won", closed_date: Date.today }
        )
        
        deal.send(:sync_deal_stage_to_attio)
      end

      it "logs and re-raises error on failure" do
        error = StandardError.new("Won update failed")
        
        expect(deals_resource).to receive(:update).and_raise(error)
        expect(logger).to receive(:error).with("Failed to mark deal as won: Won update failed")
        
        expect {
          deal.send(:sync_deal_stage_to_attio)
        }.to raise_error(StandardError, "Won update failed")
      end
    end

    context "when status changes to lost" do
      before do
        deal.define_singleton_method(:status) { "lost" }
        deal.define_singleton_method(:lost_reason) { "Competition" }
      end

      it "marks deal as lost in Attio with reason" do
        expect(deals_resource).to receive(:update).with(
          id: "existing_deal_123",
          data: { status: "lost", lost_reason: "Competition" }
        )
        
        deal.send(:sync_deal_stage_to_attio)
      end

      it "logs and re-raises error on failure" do
        error = StandardError.new("Lost update failed")
        
        expect(deals_resource).to receive(:update).and_raise(error)
        expect(logger).to receive(:error).with("Failed to mark deal as lost: Lost update failed")
        
        expect {
          deal.send(:sync_deal_stage_to_attio)
        }.to raise_error(StandardError, "Lost update failed")
      end
    end

    context "when deal has no attio_deal_id" do
      before do
        deal.attio_deal_id = nil
      end

      it "doesn't attempt to sync" do
        deal.stage_id = "new_stage"
        
        expect(deals_resource).not_to receive(:update)
        
        deal.send(:sync_deal_stage_to_attio)
      end
    end

    context "when client doesn't support deals" do
      before do
        allow(client).to receive(:respond_to?).with(:deals).and_return(false)
      end

      it "doesn't attempt to sync" do
        deal.stage_id = "new_stage"
        
        expect(deals_resource).not_to receive(:update)
        
        deal.send(:sync_deal_stage_to_attio)
      end
    end
  end

  describe "additional private method coverage" do
    describe "#deal_value with all fallbacks" do
      it "uses configured value field" do
        deal_class.attio_deal_config do
          value_field :revenue
        end
        
        deal.define_singleton_method(:revenue) { 5000 }
        expect(deal.send(:deal_value)).to eq(5000)
      end

      it "falls back to amount when no value" do
        deal_class.attio_deal_config {}
        deal.instance_eval { undef :value if respond_to?(:value) }
        deal.define_singleton_method(:amount) { 3000 }
        
        expect(deal.send(:deal_value)).to eq(3000)
      end

      it "returns 0 when no value methods exist" do
        deal_class.attio_deal_config {}
        deal.instance_eval { undef :value if respond_to?(:value) }
        
        expect(deal.send(:deal_value)).to eq(0)
      end
    end

    describe "#deal_name with all fallbacks" do
      it "uses configured name field" do
        deal_class.attio_deal_config do
          name_field :opportunity_name
        end
        
        deal.define_singleton_method(:opportunity_name) { "Big Opportunity" }
        expect(deal.send(:deal_name)).to eq("Big Opportunity")
      end

      it "falls back to title when no name" do
        deal_class.attio_deal_config {}
        deal.instance_eval { undef :name if respond_to?(:name) }
        deal.define_singleton_method(:title) { "Deal Title" }
        
        expect(deal.send(:deal_name)).to eq("Deal Title")
      end

      it "generates name from class and id as last resort" do
        deal_class.attio_deal_config {}
        deal.instance_eval { undef :name if respond_to?(:name) }
        deal.id = 999
        
        expect(deal.send(:deal_name)).to match(/#999$/)
      end
    end

    describe "#transform handling edge cases" do
      it "handles invalid transform type gracefully" do
        deal_class.attio_deal_config do
          transform_fields 12345 # Invalid type
        end
        
        data = deal.to_attio_deal
        expect(data).to include(name: "Test Deal", value: 1000)
      end

      it "applies string transform method" do
        deal_class.attio_deal_config do
          transform_fields "custom_transform"
        end
        
        deal.define_singleton_method(:custom_transform) do |data|
          data[:transformed] = true
          data
        end
        
        data = deal.to_attio_deal
        expect(data[:transformed]).to be true
      end
    end

    describe "#map_deal_field complete coverage" do
      it "handles nil config field correctly" do
        data = {}
        deal.send(:map_deal_field, data, :test_key, nil, [:fallback])
        deal.define_singleton_method(:fallback) { "fallback_value" }
        
        deal.send(:map_deal_field, data, :test_key, nil, [:fallback])
        expect(data[:test_key]).to eq("fallback_value")
      end

      it "handles empty string config field" do
        data = {}
        deal.send(:map_deal_field, data, :test_key, "", [:fallback])
        deal.define_singleton_method(:fallback) { "fallback_value" }
        
        deal.send(:map_deal_field, data, :test_key, "", [:fallback])
        expect(data[:test_key]).to eq("fallback_value")
      end

      it "stops at first non-nil fallback" do
        data = {}
        deal.define_singleton_method(:fallback1) { nil }
        deal.define_singleton_method(:fallback2) { "second" }
        deal.define_singleton_method(:fallback3) { "third" }
        
        deal.send(:map_deal_field, data, :test_key, nil, [:fallback1, :fallback2, :fallback3])
        expect(data[:test_key]).to eq("second")
      end
    end
  end

  describe "error handler coverage" do
    describe "#handle_deal_sync_error variations" do
      let(:error) { StandardError.new("Test error") }

      it "executes proc error handler" do
        handled = nil
        deal_class.attio_deal_config do
          on_error ->(e) { handled = e.message }
        end
        
        deal.send(:handle_deal_sync_error, error)
        expect(handled).to eq("Test error")
      end

      it "calls string method error handler" do
        deal_class.attio_deal_config do
          on_error "error_method"
        end
        
        deal.define_singleton_method(:error_method) do |e|
          @error_received = e.message
        end
        
        deal.send(:handle_deal_sync_error, error)
        expect(deal.instance_variable_get(:@error_received)).to eq("Test error")
      end

      it "logs when no error handler configured" do
        deal_class.attio_deal_config {}
        
        expect(logger).to receive(:error).with("Failed to sync deal to Attio: Test error")
        deal.send(:handle_deal_sync_error, error)
      end
    end
  end
end