# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attio::Rails::Concerns::Dealable Coverage Enhancement" do
  let(:deal_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"
      include Attio::Rails::Concerns::Dealable

      attio_pipeline_id "test_pipeline"
      
      def deal_name
        name || "Unnamed Deal"
      end

      def deal_value
        value || 0
      end
    end
  end

  let(:deal) { deal_class.new(name: "Test Deal", value: 1000) }
  let(:client) { instance_double(Attio::Client) }
  let(:deals_resource) { instance_double(Attio::Resources::Deals) }

  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(client).to receive(:respond_to?).with(:deals).and_return(true)
    allow(client).to receive(:deals).and_return(deals_resource)
  end

  describe "#to_attio_deal complete coverage" do
    context "stage_id field mapping" do
      it "uses configured attio_stage_field when present" do
        deal_class.attio_stage_field :custom_stage
        deal.define_singleton_method(:custom_stage) { "stage_123" }
        
        data = deal.to_attio_deal
        expect(data[:stage_id]).to eq("stage_123")
      end

      it "falls back to stage_id method when no config and stage_id exists" do
        deal_class.attio_stage_field nil
        deal.define_singleton_method(:stage_id) { "stage_456" }
        
        data = deal.to_attio_deal
        expect(data[:stage_id]).to eq("stage_456")
      end

      it "falls back to status method when no stage_id" do
        deal_class.attio_stage_field nil
        deal.define_singleton_method(:status) { "in_progress" }
        
        data = deal.to_attio_deal
        expect(data[:stage_id]).to eq("in_progress")
      end

      it "excludes stage_id when no method available" do
        deal_class.attio_stage_field nil
        data = deal.to_attio_deal
        expect(data).not_to have_key(:stage_id)
      end
    end

    context "company field mapping" do
      it "uses configured company_field_name when present" do
        deal_class.attio_deal_config do
          company_field :custom_company_id
        end
        deal.define_singleton_method(:custom_company_id) { "company_789" }
        
        data = deal.to_attio_deal
        expect(data[:company_id]).to eq("company_789")
      end

      it "uses configured field but skips if value is nil" do
        deal_class.attio_deal_config do
          company_field :custom_company_id
        end
        deal.define_singleton_method(:custom_company_id) { nil }
        
        data = deal.to_attio_deal
        expect(data).not_to have_key(:company_id)
      end

      it "falls back to company_attio_id when no config" do
        deal_class.attio_deal_config {}
        deal.define_singleton_method(:company_attio_id) { "company_fallback" }
        
        data = deal.to_attio_deal
        expect(data[:company_id]).to eq("company_fallback")
      end

      it "excludes company_id when company_attio_id is nil" do
        deal_class.attio_deal_config {}
        deal.define_singleton_method(:company_attio_id) { nil }
        
        data = deal.to_attio_deal
        expect(data).not_to have_key(:company_id)
      end
    end

    context "owner field mapping" do
      it "uses configured owner_field_name when present" do
        deal_class.attio_deal_config do
          owner_field :assigned_to_id
        end
        deal.define_singleton_method(:assigned_to_id) { "owner_123" }
        
        data = deal.to_attio_deal
        expect(data[:owner_id]).to eq("owner_123")
      end

      it "uses configured field but skips if value is nil" do
        deal_class.attio_deal_config do
          owner_field :assigned_to_id
        end
        deal.define_singleton_method(:assigned_to_id) { nil }
        
        data = deal.to_attio_deal
        expect(data).not_to have_key(:owner_id)
      end

      it "falls back to owner_attio_id when no config" do
        deal_class.attio_deal_config {}
        deal.define_singleton_method(:owner_attio_id) { "owner_fallback" }
        
        data = deal.to_attio_deal
        expect(data[:owner_id]).to eq("owner_fallback")
      end

      it "excludes owner_id when owner_attio_id is nil" do
        deal_class.attio_deal_config {}
        deal.define_singleton_method(:owner_attio_id) { nil }
        
        data = deal.to_attio_deal
        expect(data).not_to have_key(:owner_id)
      end
    end

    context "expected_close_date field mapping" do
      it "uses configured expected_close_date_field_name when present" do
        deal_class.attio_deal_config do
          expected_close_date_field :closing_date
        end
        closing = Date.today + 30
        deal.define_singleton_method(:closing_date) { closing }
        
        data = deal.to_attio_deal
        expect(data[:expected_close_date]).to eq(closing)
      end

      it "uses configured field but skips if value is nil" do
        deal_class.attio_deal_config do
          expected_close_date_field :closing_date
        end
        deal.define_singleton_method(:closing_date) { nil }
        
        data = deal.to_attio_deal
        expect(data).not_to have_key(:expected_close_date)
      end

      it "falls back to expected_close_date when no config" do
        deal_class.attio_deal_config {}
        expected_date = Date.today + 60
        deal.define_singleton_method(:expected_close_date) { expected_date }
        
        data = deal.to_attio_deal
        expect(data[:expected_close_date]).to eq(expected_date)
      end

      it "excludes expected_close_date when method returns nil" do
        deal_class.attio_deal_config {}
        deal.define_singleton_method(:expected_close_date) { nil }
        
        data = deal.to_attio_deal
        expect(data).not_to have_key(:expected_close_date)
      end
    end

    context "transform method handling" do
      it "applies proc transform when configured" do
        deal_class.attio_deal_config do
          transform_fields ->(data, record) { 
            data[:custom_field] = "proc_#{record.name}"
            data
          }
        end
        
        data = deal.to_attio_deal
        expect(data[:custom_field]).to eq("proc_Test Deal")
      end

      it "applies symbol transform when configured" do
        deal_class.attio_deal_config do
          transform_fields :add_custom_fields
        end
        
        deal.define_singleton_method(:add_custom_fields) do |data|
          data[:transformed] = true
          data
        end
        
        data = deal.to_attio_deal
        expect(data[:transformed]).to be true
      end

      it "applies string transform when configured" do
        deal_class.attio_deal_config do
          transform_fields "apply_transformations"
        end
        
        deal.define_singleton_method(:apply_transformations) do |data|
          data[:string_transform] = "applied"
          data
        end
        
        data = deal.to_attio_deal
        expect(data[:string_transform]).to eq("applied")
      end

      it "returns data unchanged for invalid transform type" do
        deal_class.attio_deal_config do
          transform_fields 123 # Invalid type
        end
        
        data = deal.to_attio_deal
        expect(data).to include(
          name: "Test Deal",
          value: 1000,
          pipeline_id: "test_pipeline"
        )
      end

      it "returns data unchanged when no transform configured" do
        deal_class.attio_deal_config {}
        
        data = deal.to_attio_deal
        expect(data).to include(
          name: "Test Deal",
          value: 1000,
          pipeline_id: "test_pipeline"
        )
      end
    end

    context "with all fields configured" do
      it "includes all fields when all values present" do
        deal_class.attio_deal_config do
          company_field :company_ref
          owner_field :owner_ref
          expected_close_date_field :close_date
          transform_fields ->(data, _) { 
            data[:source] = "test"
            data
          }
        end
        
        deal_class.attio_stage_field :deal_stage
        
        deal.define_singleton_method(:deal_stage) { "negotiation" }
        deal.define_singleton_method(:company_ref) { "comp_123" }
        deal.define_singleton_method(:owner_ref) { "user_456" }
        deal.define_singleton_method(:close_date) { Date.today + 45 }
        
        data = deal.to_attio_deal
        
        expect(data).to include(
          name: "Test Deal",
          value: 1000,
          pipeline_id: "test_pipeline",
          stage_id: "negotiation",
          company_id: "comp_123",
          owner_id: "user_456",
          expected_close_date: Date.today + 45,
          source: "test"
        )
      end
    end
  end

  describe "#map_deal_field coverage" do
    it "maps field using config field when present" do
      data = {}
      deal.send(:map_deal_field, data, :test_id, "configured_field", [:fallback1, :fallback2])
      
      deal.define_singleton_method(:configured_field) { "config_value" }
      deal.send(:map_deal_field, data, :test_id, "configured_field", [:fallback1, :fallback2])
      
      expect(data[:test_id]).to eq("config_value")
    end

    it "skips field when config field returns nil" do
      data = {}
      deal.define_singleton_method(:configured_field) { nil }
      
      deal.send(:map_deal_field, data, :test_id, "configured_field", [:fallback1, :fallback2])
      
      expect(data).not_to have_key(:test_id)
    end

    it "uses first available fallback field" do
      data = {}
      deal.define_singleton_method(:fallback1) { "fallback_value" }
      
      deal.send(:map_deal_field, data, :test_id, nil, [:fallback1, :fallback2])
      
      expect(data[:test_id]).to eq("fallback_value")
    end

    it "uses second fallback when first is nil" do
      data = {}
      deal.define_singleton_method(:fallback1) { nil }
      deal.define_singleton_method(:fallback2) { "second_fallback" }
      
      deal.send(:map_deal_field, data, :test_id, nil, [:fallback1, :fallback2])
      
      expect(data[:test_id]).to eq("second_fallback")
    end

    it "skips field when all fallbacks are nil or missing" do
      data = {}
      deal.define_singleton_method(:fallback1) { nil }
      
      deal.send(:map_deal_field, data, :test_id, nil, [:fallback1, :fallback2, :fallback3])
      
      expect(data).not_to have_key(:test_id)
    end
  end

  describe "lifecycle methods coverage" do
    describe "#current_stage_id" do
      it "returns configured stage field value" do
        deal_class.attio_stage_field :my_stage
        deal.define_singleton_method(:my_stage) { "stage_value" }
        
        expect(deal.current_stage_id).to eq("stage_value")
      end

      it "falls back to stage_id when no configured field" do
        deal_class.attio_stage_field nil
        deal.define_singleton_method(:stage_id) { "default_stage" }
        
        expect(deal.current_stage_id).to eq("default_stage")
      end

      it "falls back to status when no stage_id" do
        deal_class.attio_stage_field nil
        deal.define_singleton_method(:status) { "current_status" }
        
        expect(deal.current_stage_id).to eq("current_status")
      end

      it "returns nil when no stage methods available" do
        deal_class.attio_stage_field nil
        expect(deal.current_stage_id).to be_nil
      end
    end

    describe "#handle_deal_sync_error" do
      let(:error) { StandardError.new("Sync failed") }

      it "calls proc error handler when configured" do
        handled = false
        deal_class.attio_deal_config do
          on_error ->(err) { handled = true if err.message == "Sync failed" }
        end
        
        deal.send(:handle_deal_sync_error, error)
        expect(handled).to be true
      end

      it "calls symbol error handler when configured" do
        deal_class.attio_deal_config do
          on_error :handle_error
        end
        
        expect(deal).to receive(:handle_error).with(error)
        deal.send(:handle_deal_sync_error, error)
      end

      it "calls string error handler when configured" do
        deal_class.attio_deal_config do
          on_error "error_method"
        end
        
        expect(deal).to receive(:error_method).with(error)
        deal.send(:handle_deal_sync_error, error)
      end

      it "logs error when no handler configured" do
        deal_class.attio_deal_config {}
        logger = instance_double(Logger)
        allow(Attio::Rails).to receive(:logger).and_return(logger)
        
        expect(logger).to receive(:error).with("Failed to sync deal to Attio: Sync failed")
        deal.send(:handle_deal_sync_error, error)
      end
    end

    describe "#run_deal_callback" do
      it "executes proc callback" do
        result = nil
        deal_class.attio_deal_config do
          on_create ->(deal) { result = "created: #{deal.name}" }
        end
        
        deal.send(:run_deal_callback, :on_create, deal)
        expect(result).to eq("created: Test Deal")
      end

      it "executes symbol callback" do
        deal_class.attio_deal_config do
          on_update :update_callback
        end
        
        expect(deal).to receive(:update_callback).with("arg1", "arg2")
        deal.send(:run_deal_callback, :on_update, "arg1", "arg2")
      end

      it "executes string callback" do
        deal_class.attio_deal_config do
          on_delete "delete_handler"
        end
        
        expect(deal).to receive(:delete_handler)
        deal.send(:run_deal_callback, :on_delete)
      end

      it "does nothing when callback not configured" do
        deal_class.attio_deal_config {}
        
        expect { deal.send(:run_deal_callback, :on_random) }.not_to raise_error
      end
    end

    describe "private helper methods" do
      it "calculates deal_progress correctly" do
        deal.define_singleton_method(:deal_value) { 1000 }
        deal.define_singleton_method(:target_value) { 2000 }
        
        expect(deal.send(:deal_progress)).to eq(50.0)
      end

      it "returns 0 progress when target_value is zero" do
        deal.define_singleton_method(:deal_value) { 1000 }
        deal.define_singleton_method(:target_value) { 0 }
        
        expect(deal.send(:deal_progress)).to eq(0)
      end

      it "detects stage changes correctly" do
        deal.define_singleton_method(:current_stage_id) { "stage1" }
        deal.define_singleton_method(:stage_id) { "stage2" }
        
        expect(deal.send(:stage_changed?)).to be true
      end

      it "returns false when stages are same" do
        deal.define_singleton_method(:current_stage_id) { "stage1" }
        deal.define_singleton_method(:stage_id) { "stage1" }
        
        expect(deal.send(:stage_changed?)).to be false
      end

      it "returns false when stage methods missing" do
        expect(deal.send(:stage_changed?)).to be false
      end
    end
  end
end