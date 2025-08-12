# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attio::Rails::Concerns::Dealable Critical Logic" do
  let(:deal_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"
      include Attio::Rails::Concerns::Dealable
      
      attr_accessor :value, :status, :closed_date, :lost_reason, :attio_deal_id,
                    :company_attio_id, :owner_attio_id
      
      attio_pipeline_id "test_pipeline"
      
      def initialize(attrs = {})
        super(attrs.except(:value, :status, :closed_date, :lost_reason, :attio_deal_id,
                          :company_attio_id, :owner_attio_id))
        @value = attrs[:value]
        @status = attrs[:status]
        @closed_date = attrs[:closed_date]
        @lost_reason = attrs[:lost_reason]
        @attio_deal_id = attrs[:attio_deal_id]
        @company_attio_id = attrs[:company_attio_id]
        @owner_attio_id = attrs[:owner_attio_id]
      end
    end
  end

  let(:deal) { deal_class.new(name: "Critical Deal", value: 5000) }
  let(:client) { double("Attio::Client") }
  let(:deals_resource) { double("Attio::Resources::Deals") }

  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(Attio::Rails).to receive(:sync_enabled?).and_return(true)
    allow(Attio::Rails).to receive(:logger).and_return(Logger.new(nil))
    allow(client).to receive(:respond_to?).with(:deals).and_return(true)
    allow(client).to receive(:deals).and_return(deals_resource)
  end

  describe "Critical sync error paths" do
    context "when deal update fails with specific status" do
      before do
        deal.attio_deal_id = "existing_deal"
      end

      it "handles error when marking deal as won during sync" do
        deal.status = "won"
        deal.closed_date = Date.today
        
        allow(deals_resource).to receive(:update).and_raise(StandardError, "API Error")
        
        expect(Attio::Rails.logger).to receive(:error).with(/Failed to mark deal as won/)
        expect { deal.sync_deal_to_attio_now }.to raise_error(StandardError)
      end

      it "handles error when marking deal as lost during sync" do
        deal.status = "lost"
        deal.closed_date = Date.today
        deal.lost_reason = "No budget"
        
        allow(deals_resource).to receive(:update).and_raise(StandardError, "API Error")
        
        expect(Attio::Rails.logger).to receive(:error).with(/Failed to mark deal as lost/)
        expect { deal.sync_deal_to_attio_now }.to raise_error(StandardError)
      end

      it "handles error when updating stage during sync" do
        deal.define_singleton_method(:stage_changed?) { true }
        deal.define_singleton_method(:stage_id) { "new_stage" }
        
        allow(deals_resource).to receive(:update).and_raise(StandardError, "Stage update failed")
        
        expect(Attio::Rails.logger).to receive(:error).with(/Failed to update deal stage/)
        expect { deal.sync_deal_to_attio_now }.to raise_error(StandardError)
      end
    end
  end

  describe "Deal value calculation with fallbacks" do
    context "when no value field is configured" do
      it "uses value method when available" do
        deal.value = 1500
        expect(deal.send(:deal_value)).to eq(1500)
      end

      it "falls back to amount method when value is not available" do
        deal.instance_eval { undef :value if respond_to?(:value) }
        deal.define_singleton_method(:amount) { 2500 }
        expect(deal.send(:deal_value)).to eq(2500)
      end

      it "returns 0 when no value methods are available" do
        deal.instance_eval { undef :value if respond_to?(:value) }
        expect(deal.send(:deal_value)).to eq(0)
      end
    end

    context "with configured value field" do
      before do
        deal_class.attio_deal_config do
          value_field :custom_amount
        end
      end

      it "uses configured field when present" do
        deal.define_singleton_method(:custom_amount) { 3500 }
        expect(deal.send(:deal_value)).to eq(3500)
      end
    end
  end

  describe "Field mapping logic" do
    it "maps fields correctly when configured field exists" do
      deal_class.attio_deal_config do
        company_field :organization_id
      end
      
      deal.define_singleton_method(:organization_id) { "org_123" }
      
      result = deal.to_attio_deal
      expect(result[:company_id]).to eq("org_123")
    end

    it "falls back to default fields when configured field is nil" do
      deal_class.attio_deal_config do
        company_field :nonexistent_field
      end
      
      deal.define_singleton_method(:company_attio_id) { "comp_456" }
      
      result = deal.to_attio_deal
      expect(result[:company_id]).to eq("comp_456")
    end

    it "excludes field when no value is present" do
      deal_class.attio_deal_config do
        owner_field :assigned_to
      end
      
      result = deal.to_attio_deal
      expect(result).not_to have_key(:owner_id)
    end
  end

  describe "Error handler execution" do
    context "with configured error handler" do
      it "calls proc error handler" do
        error_handled = false
        
        deal_class.attio_deal_config do
          on_error ->(error) { error_handled = true }
        end
        
        error = StandardError.new("Test error")
        deal.send(:handle_deal_sync_error, error)
        
        expect(error_handled).to be true
      end

      it "calls method error handler" do
        deal_class.attio_deal_config do
          on_error :custom_error_handler
        end
        
        error_handled = false
        deal.define_singleton_method(:custom_error_handler) do |error|
          error_handled = true
        end
        
        error = StandardError.new("Test error")
        deal.send(:handle_deal_sync_error, error)
        
        expect(error_handled).to be true
      end
    end

    context "without error handler in production" do
      it "logs error and doesn't raise" do
        allow(::Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        
        error = StandardError.new("Production error")
        expect(Attio::Rails.logger).to receive(:error).with(/Failed to sync deal to Attio/)
        
        expect { deal.send(:handle_deal_sync_error, error) }.not_to raise_error
      end
    end

    context "without error handler in development" do
      it "logs error and raises" do
        allow(::Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        
        error = StandardError.new("Development error")
        expect(Attio::Rails.logger).to receive(:error).with(/Failed to sync deal to Attio/)
        
        expect { deal.send(:handle_deal_sync_error, error) }.to raise_error(StandardError)
      end
    end
  end

  describe "Pipeline ID resolution" do
    it "uses class-level pipeline_id when set" do
      deal_class.attio_pipeline_id("class_pipeline")
      expect(deal.send(:pipeline_id)).to eq("class_pipeline")
    end

    it "falls back to configuration pipeline_id" do
      deal_class.attio_pipeline_id(nil)
      deal_class.attio_deal_config do
        pipeline_id "config_pipeline"
      end
      
      expect(deal.send(:pipeline_id)).to eq("config_pipeline")
    end
  end
end