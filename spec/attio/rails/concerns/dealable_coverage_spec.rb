# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attio::Rails::Concerns::Dealable Coverage Tests" do
  let(:deal_class) do
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"
      include Attio::Rails::Concerns::Dealable
      
      attr_accessor :attio_deal_id, :value, :stage_id, :status, :closed_date, 
                    :lost_reason, :company_attio_id, :owner_attio_id, :current_stage_id
      
      def initialize(attrs = {})
        super(attrs.except(:attio_deal_id, :value, :stage_id, :status, :closed_date, 
                          :lost_reason, :company_attio_id, :owner_attio_id, :current_stage_id))
        @attio_deal_id = attrs[:attio_deal_id]
        @value = attrs[:value]
        @stage_id = attrs[:stage_id]
        @status = attrs[:status]
        @closed_date = attrs[:closed_date]
        @lost_reason = attrs[:lost_reason]
        @company_attio_id = attrs[:company_attio_id]
        @owner_attio_id = attrs[:owner_attio_id]
        @current_stage_id = attrs[:current_stage_id]
      end
      
      def id
        @id ||= rand(1000)
      end
      
      def update!(attrs)
        attrs.each { |k, v| send("#{k}=", v) }
        self
      end
      
      def update_column(column, value)
        send("#{column}=", value)
      end
    end
    stub_const("TestDeal", klass)
    klass
  end
  
  let(:deal) { deal_class.new(name: "Test Deal", value: 5000, attio_deal_id: "deal_123", stage_id: "prospect") }
  let(:client) { double("Attio::Client") }
  let(:deals_resource) { double("Attio::Resources::Deals") }
  
  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(Attio::Rails).to receive(:sync_enabled?).and_return(true)
    allow(Attio::Rails).to receive(:background_sync?).and_return(false)
    allow(Attio::Rails).to receive(:logger).and_return(Logger.new(nil))
    allow(client).to receive(:respond_to?).with(:deals).and_return(true)
    allow(client).to receive(:deals).and_return(deals_resource)
    
    deal_class.attio_pipeline_id("test_pipeline")
  end
  
  describe "Deal value calculation with all fallbacks" do
    it "uses value method as first priority" do
      deal.value = 7500
      expect(deal.send(:deal_value)).to eq(7500)
    end
    
    it "falls back to amount method when value is nil" do
      value_deal = deal_class.new(name: "Test")
      value_deal.instance_eval do
        @value = nil
        def amount
          3500
        end
      end
      
      expect(value_deal.send(:deal_value)).to eq(3500)
    end
    
    it "returns 0 when no value methods are available" do
      empty_deal = deal_class.new(name: "Empty")
      empty_deal.instance_eval do
        @value = nil
      end
      
      expect(empty_deal.send(:deal_value)).to eq(0)
    end
    
    it "uses configured value field over defaults" do
      deal_class.attio_deal_config do
        value_field :revenue
      end
      
      revenue_deal = deal_class.new(name: "Revenue Deal")
      revenue_deal.define_singleton_method(:revenue) { 12000 }
      revenue_deal.value = 5000 # This should be ignored
      
      expect(revenue_deal.send(:deal_value)).to eq(12000)
    end
    
    it "falls back through configured field to amount to zero" do
      deal_class.attio_deal_config do
        value_field :missing_field
      end
      
      fallback_deal = deal_class.new(name: "Fallback")
      fallback_deal.instance_eval do
        @value = nil
        def amount
          nil
        end
      end
      
      expect(fallback_deal.send(:deal_value)).to eq(0)
    end
  end
  
  describe "Stage field resolution with all paths" do
    it "uses configured stage field as first priority" do
      deal_class.attio_deal_config do
        stage_field :pipeline_stage
      end
      
      stage_deal = deal_class.new(name: "Stage Deal")
      stage_deal.define_singleton_method(:pipeline_stage) { "closing" }
      stage_deal.current_stage_id = "negotiation"
      stage_deal.stage_id = "qualification"
      
      expect(stage_deal.current_stage_id).to eq("closing")
    end
    
    it "falls back to current_stage_id accessor" do
      stage_deal = deal_class.new(name: "Stage Deal")
      stage_deal.current_stage_id = "negotiation"
      stage_deal.stage_id = "qualification"
      
      expect(stage_deal.current_stage_id).to eq("negotiation")
    end
    
    it "falls back to stage_id as last resort" do
      stage_deal = deal_class.new(name: "Stage Deal")
      stage_deal.current_stage_id = nil
      stage_deal.stage_id = "qualification"
      
      expect(stage_deal.current_stage_id).to eq("qualification")
    end
    
    it "returns nil when no stage fields have values" do
      empty_deal = deal_class.new(name: "Empty")
      expect(empty_deal.current_stage_id).to be_nil
    end
    
    it "handles all nil values in fallback chain" do
      deal_class.attio_deal_config do
        stage_field :custom_stage
      end
      
      nil_deal = deal_class.new(name: "Nil Deal")
      nil_deal.define_singleton_method(:custom_stage) { nil }
      nil_deal.current_stage_id = nil
      nil_deal.stage_id = nil
      
      expect(nil_deal.current_stage_id).to be_nil
    end
  end
  
  describe "Callback execution with error handling" do
    it "executes before_attio_deal_sync callback" do
      callback_executed = false
      
      deal_class.attio_deal_config do
        before_sync -> { callback_executed = true }
      end
      
      # Need to capture the variable in the lambda's binding
      deal.instance_variable_set(:@callback_executed_marker, false)
      deal_class.attio_deal_config do
        before_sync -> { @callback_executed_marker = true }
      end
      
      allow(deals_resource).to receive(:update).and_return({ "id" => "deal_123" })
      
      deal.sync_deal_to_attio_now
      expect(deal.instance_variable_get(:@callback_executed_marker)).to be true
    end
    
    it "logs and continues when callback raises error" do
      deal_class.attio_deal_config do
        after_sync ->(_result) { raise "Callback failed" }
      end
      
      allow(deals_resource).to receive(:update).and_return({ "id" => "deal_123" })
      
      expect(Attio::Rails.logger).to receive(:error).with(/Callback error in after_sync/)
      
      result = deal.sync_deal_to_attio_now
      expect(result).to eq({ "id" => "deal_123" })
    end
  end
  
  describe "Error handling in handle_deal_sync_error" do
    it "raises in development environment" do
      allow(::Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      
      error = StandardError.new("Dev error")
      expect(Attio::Rails.logger).to receive(:error).with(/Failed to sync deal to Attio/)
      
      expect { deal.send(:handle_deal_sync_error, error) }.to raise_error(StandardError)
    end
    
    it "only logs in production environment" do
      allow(::Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      
      error = StandardError.new("Prod error")
      expect(Attio::Rails.logger).to receive(:error).with(/Failed to sync deal to Attio/)
      
      expect { deal.send(:handle_deal_sync_error, error) }.not_to raise_error
    end
    
    it "calls configured error handler" do
      error_handled = false
      
      deal_class.attio_deal_config do
        on_error ->(err) { error_handled = true }
      end
      
      error = StandardError.new("Test error")
      deal.send(:handle_deal_sync_error, error)
      
      expect(error_handled).to be true
    end
  end
  
  describe "Field mapping with various configurations" do
    it "maps company field from configured source" do
      deal_class.attio_deal_config do
        company_field :organization_id
      end
      
      deal.define_singleton_method(:organization_id) { "org_789" }
      
      result = deal.to_attio_deal
      expect(result[:company_id]).to eq("org_789")
    end
    
    it "falls back to company_attio_id when configured field is nil" do
      deal_class.attio_deal_config do
        company_field :org_field
      end
      
      deal.define_singleton_method(:org_field) { nil }
      deal.company_attio_id = "company_456"
      
      result = deal.to_attio_deal
      expect(result[:company_id]).to eq("company_456")
    end
    
    it "excludes field when no company data available" do
      deal_class.attio_deal_config do
        company_field :missing_field
      end
      
      deal.company_attio_id = nil
      
      result = deal.to_attio_deal
      expect(result).not_to have_key(:company_id)
    end
  end
  
  describe "DealConfig setter methods coverage" do
    it "sets value_field configuration" do
      config = deal_class::DealConfig.new(deal_class)
      config.value_field(:custom_value)
      expect(config.value_field).to eq(:custom_value)
    end
    
    it "sets stage_field configuration" do
      config = deal_class::DealConfig.new(deal_class)
      config.stage_field(:pipeline_stage)
      expect(config.stage_field).to eq(:pipeline_stage)
    end
    
    it "sets company_field configuration" do
      config = deal_class::DealConfig.new(deal_class)
      config.company_field(:org_id)
      expect(config.company_field_name).to eq(:org_id)
    end
    
    it "sets owner_field configuration" do
      config = deal_class::DealConfig.new(deal_class)
      config.owner_field(:assigned_to)
      expect(config.owner_field_name).to eq(:assigned_to)
    end
    
    it "sets expected_close_date_field configuration" do
      config = deal_class::DealConfig.new(deal_class)
      config.expected_close_date_field(:close_by)
      expect(config.expected_close_date_field_name).to eq(:close_by)
    end
    
    it "sets on_error handler as proc" do
      config = deal_class::DealConfig.new(deal_class)
      handler = ->(e) { puts e }
      config.on_error(handler)
      expect(config.error_handler).to eq(handler)
    end
    
    it "sets on_error handler as symbol" do
      config = deal_class::DealConfig.new(deal_class)
      config.on_error(:handle_error)
      expect(config.error_handler).to eq(:handle_error)
    end
  end
end