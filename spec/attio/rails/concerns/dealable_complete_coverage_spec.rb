# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attio::Rails::Concerns::Dealable Complete Coverage" do
  let(:deal_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"
      include Attio::Rails::Concerns::Dealable
      
      attio_pipeline_id "test_pipeline"
      
      # Default methods that can be overridden
      def deal_name
        name || "Default Deal"
      end
      
      def deal_value  
        value || 0
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

  describe "Won and Lost deal scenarios" do
    before do
      deal.attio_deal_id = "deal_123"
    end

    describe "#mark_as_won!" do
      context "when configured to track won deals" do
        before do
          deal_class.track_won_deals
        end

        it "marks deal as won in Attio" do
          expect(deals_resource).to receive(:mark_won).with(
            id: "deal_123",
            won_date: anything
          )
          expect(deal).to receive(:update!).with(
            status: "won",
            closed_date: anything
          )
          
          deal.mark_as_won!
        end

        it "runs on_won callback when defined" do
          callback_executed = false
          deal_class.attio_deal_config do
            on_won { callback_executed = true }
          end
          
          allow(deals_resource).to receive(:mark_won)
          allow(deal).to receive(:update!)
          
          deal.mark_as_won!
          expect(callback_executed).to be true
        end
      end

      context "when not configured to track won deals" do
        it "doesn't mark deal as won" do
          expect(deals_resource).not_to receive(:mark_won)
          expect(deal).not_to receive(:update!)
          
          deal.mark_as_won!
        end
      end
    end

    describe "#mark_as_lost!" do
      context "when configured to track lost deals" do
        before do
          deal_class.track_lost_deals
        end

        it "marks deal as lost with reason in Attio" do
          expect(deals_resource).to receive(:mark_lost).with(
            id: "deal_123",
            lost_reason: "No budget",
            lost_date: anything
          )
          expect(deal).to receive(:update!).with(
            status: "lost",
            closed_date: anything,
            lost_reason: "No budget"
          )
          
          deal.mark_as_lost!(lost_reason: "No budget")
        end

        it "runs on_lost callback when defined" do
          callback_executed = false
          deal_class.attio_deal_config do
            on_lost { callback_executed = true }
          end
          
          allow(deals_resource).to receive(:mark_lost)
          allow(deal).to receive(:update!)
          
          deal.mark_as_lost!
          expect(callback_executed).to be true
        end
      end

      context "when not configured to track lost deals" do
        it "doesn't mark deal as lost" do
          expect(deals_resource).not_to receive(:mark_lost)
          expect(deal).not_to receive(:update!)
          
          deal.mark_as_lost!
        end
      end
    end
  end

  describe "after_attio_deal_sync callback" do
    it "executes after_attio_deal_sync when defined" do
      callback_result = nil
      
      deal.define_singleton_method(:after_attio_deal_sync) do |result|
        callback_result = result
      end
      
      response = { "data" => { "id" => "new_deal" } }
      allow(deals_resource).to receive(:create).and_return(response)
      
      deal.sync_deal_to_attio_now
      expect(callback_result).to eq(response)
    end

    it "continues normally when after_attio_deal_sync is not defined" do
      response = { "data" => { "id" => "new_deal" } }
      allow(deals_resource).to receive(:create).and_return(response)
      
      expect { deal.sync_deal_to_attio_now }.not_to raise_error
    end
  end

  describe "transform_method as Symbol and String" do
    context "when transform_method is a Symbol" do
      it "calls the method specified by symbol" do
        deal_class.attio_deal_config do
          transform_fields :apply_custom_transform
        end
        
        deal.define_singleton_method(:apply_custom_transform) do |data|
          data[:custom_field] = "transformed_by_symbol"
          data
        end
        
        result = deal.to_attio_deal
        expect(result[:custom_field]).to eq("transformed_by_symbol")
      end
    end

    context "when transform_method is a String" do
      it "calls the method specified by string" do
        deal_class.attio_deal_config do
          transform_fields "string_transform_method"
        end
        
        deal.define_singleton_method(:string_transform_method) do |data|
          data[:string_transformed] = true
          data
        end
        
        result = deal.to_attio_deal
        expect(result[:string_transformed]).to be true
      end
    end
  end

  describe "deal_name fallback chain complete" do
    context "with configured name_field" do
      it "uses the configured field when present" do
        deal_class.attio_deal_config do
          name_field :opportunity_title
        end
        
        deal.define_singleton_method(:opportunity_title) { "Opportunity Name" }
        expect(deal.send(:deal_name)).to eq("Opportunity Name")
      end
    end

    context "when name method exists" do
      it "uses name method as fallback" do
        deal_class.attio_deal_config {}
        deal.name = "Deal Name"
        expect(deal.send(:deal_name)).to eq("Deal Name")
      end
    end

    context "when title method exists" do
      it "uses title as second fallback" do
        deal_class.attio_deal_config {}
        # Remove name method
        deal.instance_eval { undef :name if respond_to?(:name) }
        deal.define_singleton_method(:title) { "Deal Title" }
        
        expect(deal.send(:deal_name)).to eq("Deal Title")
      end
    end

    context "when no name methods exist" do
      it "generates name from class and id" do
        deal_class.attio_deal_config {}
        # Remove name and title methods
        deal.instance_eval { undef :name if respond_to?(:name) }
        deal.id = 42
        
        expected_name = "#{deal.class.name} #42"
        expect(deal.send(:deal_name)).to eq(expected_name)
      end
    end
  end

  describe "deal_value fallback chain complete" do
    context "with configured value_field" do
      it "uses the configured field when present" do
        deal_class.attio_deal_config do
          value_field :total_revenue
        end
        
        deal.define_singleton_method(:total_revenue) { 7500 }
        expect(deal.send(:deal_value)).to eq(7500)
      end
    end

    context "when value method exists" do
      it "uses value method as fallback" do
        deal_class.attio_deal_config {}
        deal.value = 5000
        expect(deal.send(:deal_value)).to eq(5000)
      end
    end

    context "when amount method exists" do
      it "uses amount as second fallback" do
        deal_class.attio_deal_config {}
        # Remove value method
        deal.instance_eval { undef :value if respond_to?(:value) }
        deal.define_singleton_method(:amount) { 3500 }
        
        expect(deal.send(:deal_value)).to eq(3500)
      end
    end

    context "when no value methods exist" do
      it "returns 0 as default" do
        deal_class.attio_deal_config {}
        # Remove value method
        deal.instance_eval { undef :value if respond_to?(:value) }
        
        expect(deal.send(:deal_value)).to eq(0)
      end
    end
  end

  describe "current_stage_id method" do
    context "with configured attio_stage_field" do
      it "returns the value from configured field" do
        deal_class.attio_stage_field :pipeline_stage
        deal.define_singleton_method(:pipeline_stage) { "negotiation" }
        
        expect(deal.current_stage_id).to eq("negotiation")
      end
    end

    context "without configured field" do
      before do
        deal_class.attio_stage_field nil
      end

      it "falls back to stage_id method" do
        deal.define_singleton_method(:stage_id) { "prospecting" }
        expect(deal.current_stage_id).to eq("prospecting")
      end

      it "falls back to status method when no stage_id" do
        deal.define_singleton_method(:status) { "in_progress" }
        expect(deal.current_stage_id).to eq("in_progress")
      end

      it "returns nil when no stage methods available" do
        expect(deal.current_stage_id).to be_nil
      end
    end
  end

  describe "handle_deal_sync_error with Symbol and String handlers" do
    let(:error) { StandardError.new("Sync error occurred") }

    context "when error handler is a Symbol" do
      it "calls the method specified by symbol" do
        deal_class.attio_deal_config do
          on_error :handle_sync_error
        end
        
        error_handled = nil
        deal.define_singleton_method(:handle_sync_error) do |err|
          error_handled = err.message
        end
        
        deal.send(:handle_deal_sync_error, error)
        expect(error_handled).to eq("Sync error occurred")
      end
    end

    context "when error handler is a String" do
      it "calls the method specified by string" do
        deal_class.attio_deal_config do
          on_error "string_error_handler"
        end
        
        error_handled = nil
        deal.define_singleton_method(:string_error_handler) do |err|
          error_handled = err.message
        end
        
        deal.send(:handle_deal_sync_error, error)
        expect(error_handled).to eq("Sync error occurred")
      end
    end

    context "when no error handler configured" do
      it "logs the error" do
        deal_class.attio_deal_config {}
        
        expect(logger).to receive(:error).with("Failed to sync deal to Attio: Sync error occurred")
        deal.send(:handle_deal_sync_error, error)
      end
    end
  end

  describe "field configurations with nil and instance variable fallbacks" do
    describe "company_field configuration" do
      context "when company_field is nil" do
        it "falls back to company_attio_id instance variable" do
          deal_class.attio_deal_config do
            company_field nil
          end
          
          deal.define_singleton_method(:company_attio_id) { "company_456" }
          
          result = deal.to_attio_deal
          expect(result[:company_id]).to eq("company_456")
        end

        it "excludes company_id when company_attio_id is nil" do
          deal_class.attio_deal_config do
            company_field nil
          end
          
          deal.define_singleton_method(:company_attio_id) { nil }
          
          result = deal.to_attio_deal
          expect(result).not_to have_key(:company_id)
        end
      end

      context "when company_field is configured but returns nil" do
        it "doesn't include company_id in result" do
          deal_class.attio_deal_config do
            company_field :custom_company
          end
          
          deal.define_singleton_method(:custom_company) { nil }
          
          result = deal.to_attio_deal
          expect(result).not_to have_key(:company_id)
        end
      end
    end

    describe "owner_field configuration" do
      context "when owner_field is nil" do
        it "falls back to owner_attio_id instance variable" do
          deal_class.attio_deal_config do
            owner_field nil
          end
          
          deal.define_singleton_method(:owner_attio_id) { "user_789" }
          
          result = deal.to_attio_deal
          expect(result[:owner_id]).to eq("user_789")
        end

        it "excludes owner_id when owner_attio_id is nil" do
          deal_class.attio_deal_config do
            owner_field nil
          end
          
          deal.define_singleton_method(:owner_attio_id) { nil }
          
          result = deal.to_attio_deal
          expect(result).not_to have_key(:owner_id)
        end
      end

      context "when owner_field is configured but returns nil" do
        it "doesn't include owner_id in result" do
          deal_class.attio_deal_config do
            owner_field :assigned_user
          end
          
          deal.define_singleton_method(:assigned_user) { nil }
          
          result = deal.to_attio_deal
          expect(result).not_to have_key(:owner_id)
        end
      end
    end

    describe "expected_close_date_field configuration" do
      context "when expected_close_date_field is nil" do
        it "falls back to expected_close_date instance variable" do
          deal_class.attio_deal_config do
            expected_close_date_field nil
          end
          
          expected_date = Date.today + 30
          deal.define_singleton_method(:expected_close_date) { expected_date }
          
          result = deal.to_attio_deal
          expect(result[:expected_close_date]).to eq(expected_date)
        end

        it "excludes expected_close_date when instance variable is nil" do
          deal_class.attio_deal_config do
            expected_close_date_field nil
          end
          
          deal.define_singleton_method(:expected_close_date) { nil }
          
          result = deal.to_attio_deal
          expect(result).not_to have_key(:expected_close_date)
        end
      end

      context "when expected_close_date_field is configured but returns nil" do
        it "doesn't include expected_close_date in result" do
          deal_class.attio_deal_config do
            expected_close_date_field :target_close_date
          end
          
          deal.define_singleton_method(:target_close_date) { nil }
          
          result = deal.to_attio_deal
          expect(result).not_to have_key(:expected_close_date)
        end
      end
    end
  end

  describe "Additional edge cases for complete coverage" do
    describe "#sync_deal_to_attio_now when is_won? or is_lost? are true" do
      before do
        deal.attio_deal_id = "existing_deal"
        allow(deals_resource).to receive(:update).and_return({ "data" => { "id" => "existing_deal" } })
      end

      it "marks as won when is_won? returns true" do
        deal.define_singleton_method(:is_won?) { true }
        
        expect(deals_resource).to receive(:mark_won).with(
          id: "existing_deal"
        )
        
        deal.sync_deal_to_attio_now
      end

      it "marks as lost when is_lost? returns true with reason" do
        deal.define_singleton_method(:is_lost?) { true }
        deal.define_singleton_method(:lost_reason) { "Budget constraints" }
        
        expect(deals_resource).to receive(:mark_lost).with(
          id: "existing_deal",
          lost_reason: "Budget constraints"
        )
        
        deal.sync_deal_to_attio_now
      end
    end

    describe "#update_stage! method" do
      before do
        deal.attio_deal_id = "deal_123"
      end

      it "updates stage locally and in Attio" do
        new_stage = "closed_won"
        
        expect(deal).to receive(:update!).with(current_stage_id: new_stage)
        expect(deals_resource).to receive(:update).with(
          id: "deal_123",
          data: { stage_id: new_stage }
        )
        
        deal.update_stage!(new_stage)
      end

      it "runs on_stage_change callback when defined" do
        callback_executed = false
        deal_class.attio_deal_config do
          on_stage_change { callback_executed = true }
        end
        
        allow(deal).to receive(:update!)
        allow(deals_resource).to receive(:update)
        
        deal.update_stage!("new_stage")
        expect(callback_executed).to be true
      end
    end

    describe "Private callback methods" do
      it "executes before_attio_deal_sync callback" do
        callback_executed = false
        
        deal.define_singleton_method(:before_attio_deal_sync) do
          callback_executed = true
        end
        
        allow(deals_resource).to receive(:create).and_return({ "data" => { "id" => "new_deal" } })
        
        deal.sync_deal_to_attio_now
        expect(callback_executed).to be true
      end

      it "continues when before_attio_deal_sync is not defined" do
        allow(deals_resource).to receive(:create).and_return({ "data" => { "id" => "new_deal" } })
        
        expect { deal.sync_deal_to_attio_now }.not_to raise_error
      end
    end
  end
end