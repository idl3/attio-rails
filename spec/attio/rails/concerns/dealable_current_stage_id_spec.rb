# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attio::Rails::Concerns::Dealable#current_stage_id" do
  # Create a base class first
  before(:all) do
    @base_deal_class = Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"
      include Attio::Rails::Concerns::Dealable
      
      def self.name
        "TestDealModel"
      end
      
      def deal_name
        name || "Test Deal"
      end
      
      def deal_value
        value || 1000
      end
    end
    
    # Set default pipeline
    @base_deal_class.attio_pipeline_id = "test_pipeline"
  end
  
  let(:deal_class) { @base_deal_class }
  let(:deal) { deal_class.new(name: "Test Deal", value: 1000) }

  describe "#current_stage_id method logic branches" do
    context "Branch 1: attio_stage_field is present AND method exists" do
      it "returns value from configured field when both conditions are true" do
        # Set attio_stage_field to a custom field
        deal_class.attio_stage_field = :my_custom_stage
        
        # Define the custom method
        deal.define_singleton_method(:my_custom_stage) { "custom_stage_value" }
        
        # This should take the first branch (line 312-313)
        expect(deal.current_stage_id).to eq("custom_stage_value")
      end

      it "uses configured field even when stage_id also exists" do
        # Configure custom field
        deal_class.attio_stage_field = :priority_stage
        
        # Define both methods
        deal.define_singleton_method(:priority_stage) { "priority_value" }
        deal.define_singleton_method(:stage_id) { "fallback_stage" }
        deal.define_singleton_method(:status) { "fallback_status" }
        
        # Should use configured field, not fallbacks
        expect(deal.current_stage_id).to eq("priority_value")
      end
    end

    context "Branch 2: attio_stage_field is present BUT method doesn't exist" do
      it "falls back to stage_id when configured field method is missing" do
        # Set attio_stage_field to a non-existent method
        deal_class.attio_stage_field = :nonexistent_method
        
        # Define stage_id fallback
        deal.define_singleton_method(:stage_id) { "stage_id_value" }
        
        # Should skip first condition (method doesn't exist) and use stage_id (line 314-315)
        expect(deal.current_stage_id).to eq("stage_id_value")
      end
    end

    context "Branch 3: attio_stage_field is nil/blank" do
      it "uses stage_id when attio_stage_field is nil" do
        # Explicitly set to nil
        deal_class.attio_stage_field = nil
        
        # Define stage_id
        deal.define_singleton_method(:stage_id) { "direct_stage_id" }
        
        # Should skip first condition (field not present) and use stage_id (line 314-315)
        expect(deal.current_stage_id).to eq("direct_stage_id")
      end

      it "uses stage_id when attio_stage_field is empty string" do
        # Set to empty string
        deal_class.attio_stage_field ""
        
        # Define stage_id
        deal.define_singleton_method(:stage_id) { "stage_from_id" }
        
        # Should use stage_id (line 314-315)
        expect(deal.current_stage_id).to eq("stage_from_id")
      end
    end

    context "Branch 4: No attio_stage_field, no stage_id, but has status" do
      it "falls back to status when stage_id doesn't exist" do
        # No configured field
        deal_class.attio_stage_field = nil
        
        # Don't define stage_id, only status
        deal.define_singleton_method(:status) { "status_value" }
        
        # Should skip first two conditions and use status (line 316-317)
        expect(deal.current_stage_id).to eq("status_value")
      end

      it "uses status even when it's the only method available" do
        # Clear any configuration
        deal_class.attio_stage_field = nil
        
        # Only define status, ensure no stage_id method exists
        if deal.respond_to?(:stage_id)
          deal.instance_eval { undef :stage_id }
        end
        deal.define_singleton_method(:status) { "only_status" }
        
        # Should reach the status branch (line 316-317)
        expect(deal.current_stage_id).to eq("only_status")
      end
    end

    context "Branch 5: No methods available at all" do
      it "returns nil when no stage methods exist" do
        # No configuration
        deal_class.attio_stage_field = nil
        
        # Ensure no fallback methods exist
        if deal.respond_to?(:stage_id)
          deal.instance_eval { undef :stage_id }
        end
        if deal.respond_to?(:status)
          deal.instance_eval { undef :status }
        end
        
        # Should return nil (line 318 - implicit nil at end)
        expect(deal.current_stage_id).to be_nil
      end
    end

    context "Edge cases and combinations" do
      it "handles when configured field returns nil" do
        deal_class.attio_stage_field = :nullable_stage
        deal.define_singleton_method(:nullable_stage) { nil }
        deal.define_singleton_method(:stage_id) { "backup_stage" }
        
        # Should return nil from configured field, not fall back
        expect(deal.current_stage_id).to be_nil
      end

      it "handles when stage_id returns nil but status exists" do
        deal_class.attio_stage_field = nil
        deal.define_singleton_method(:stage_id) { nil }
        deal.define_singleton_method(:status) { "status_backup" }
        
        # Should return nil from stage_id, not fall back to status
        expect(deal.current_stage_id).to be_nil
      end

      it "correctly identifies present? for various field values" do
        # Test with symbol
        deal_class.attio_stage_field = :symbol_field
        deal.define_singleton_method(:symbol_field) { "symbol_value" }
        expect(deal.current_stage_id).to eq("symbol_value")
        
        # Test with string
        deal_class.attio_stage_field = "string_field"
        deal.define_singleton_method(:string_field) { "string_value" }
        expect(deal.current_stage_id).to eq("string_value")
      end
    end

    context "Integration with stage_changed? method" do
      it "works correctly with stage_changed? when using configured field" do
        deal_class.attio_stage_field = :tracked_stage
        
        # Set up current and new stages
        deal.define_singleton_method(:tracked_stage) { "current" }
        deal.define_singleton_method(:stage_id) { "new" }
        
        # current_stage_id should use tracked_stage
        expect(deal.current_stage_id).to eq("current")
        
        # stage_changed? should detect difference
        expect(deal.send(:stage_changed?)).to be true
      end

      it "works correctly with stage_changed? when using stage_id" do
        deal_class.attio_stage_field = nil
        
        # Define both methods
        deal.define_singleton_method(:current_stage_id) { "old_stage" }
        deal.define_singleton_method(:stage_id) { "new_stage" }
        
        expect(deal.send(:stage_changed?)).to be true
      end
    end
  end

  describe "Real-world scenarios" do
    it "handles ActiveRecord model with actual stage attributes" do
      # Simulate a real model with stage attributes
      deal.instance_eval do
        @stage_id = "negotiation"
        def stage_id
          @stage_id
        end
      end
      
      deal_class.attio_stage_field = nil
      expect(deal.current_stage_id).to eq("negotiation")
    end

    it "handles model with custom stage field configuration" do
      # Configure to use a custom field
      deal_class.attio_stage_field = :pipeline_stage_identifier
      
      # Simulate custom field
      deal.instance_eval do
        def pipeline_stage_identifier
          "qualification"
        end
      end
      
      expect(deal.current_stage_id).to eq("qualification")
    end

    it "handles model transitioning through stages" do
      # Start with one stage
      deal_class.attio_stage_field = :deal_stage
      deal.define_singleton_method(:deal_stage) { @stage ||= "prospecting" }
      
      expect(deal.current_stage_id).to eq("prospecting")
      
      # Transition to new stage
      deal.instance_variable_set(:@stage, "closing")
      expect(deal.current_stage_id).to eq("closing")
    end
  end
end