# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Dealable current_stage_id direct tests" do
  let(:client) { instance_double(Attio::Client) }
  let(:deals_resource) { instance_double(Attio::Resources::Deals) }

  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(client).to receive(:respond_to?).with(:deals).and_return(true)
    allow(client).to receive(:deals).and_return(deals_resource)
  end

  describe "current_stage_id method execution paths" do
    # Test each branch directly using the existing TestDeal class
    context "using TestDeal class" do
      let(:deal) { TestDeal.new(name: "Test", value: 1000) }

      it "executes line 312-313: configured field present and method exists" do
        # Configure the stage field
        TestDeal.class_eval do
          attio_stage_field :custom_stage_method
        end
        
        # Add the method
        deal.define_singleton_method(:custom_stage_method) { "configured_stage" }
        
        # Execute and verify
        result = deal.current_stage_id
        expect(result).to eq("configured_stage")
        
        # Reset for other tests
        TestDeal.attio_stage_field nil
      end

      it "executes line 314-315: falls back to stage_id" do
        # Ensure no configured field
        TestDeal.attio_stage_field nil
        
        # Set stage_id
        deal.stage_id = "fallback_stage_id"
        
        # Execute and verify
        result = deal.current_stage_id
        expect(result).to eq("fallback_stage_id")
      end

      it "executes line 316-317: falls back to status" do
        # Ensure no configured field
        TestDeal.attio_stage_field nil
        
        # Remove stage_id, add status
        deal.stage_id = nil
        deal.status = "status_fallback"
        
        # Execute and verify
        result = deal.current_stage_id
        expect(result).to eq("status_fallback")
      end

      it "executes line 318: returns nil when no methods available" do
        # Ensure no configured field
        TestDeal.attio_stage_field nil
        
        # Remove all stage methods
        deal.stage_id = nil
        deal.status = nil
        
        # Execute and verify
        result = deal.current_stage_id
        expect(result).to be_nil
      end
    end

    # Test with a fresh class to ensure isolation
    context "using isolated class" do
      let(:isolated_class) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "test_models"
          include Attio::Rails::Concerns::Dealable
          
          def self.name
            "IsolatedDeal"
          end
          
          def deal_name
            "Test"
          end
          
          def deal_value
            100
          end
        end
      end

      it "covers all branches in sequence" do
        deal = isolated_class.new
        
        # Branch 1: No configuration, no methods -> nil
        isolated_class.attio_stage_field nil
        expect(deal.current_stage_id).to be_nil
        
        # Branch 2: Add status method -> uses status
        deal.define_singleton_method(:status) { "from_status" }
        expect(deal.current_stage_id).to eq("from_status")
        
        # Branch 3: Add stage_id method -> uses stage_id (priority over status)
        deal.define_singleton_method(:stage_id) { "from_stage_id" }
        expect(deal.current_stage_id).to eq("from_stage_id")
        
        # Branch 4: Configure custom field -> uses configured field
        isolated_class.attio_stage_field :my_field
        deal.define_singleton_method(:my_field) { "from_configured" }
        expect(deal.current_stage_id).to eq("from_configured")
      end
    end

    # Direct method invocation to ensure coverage
    context "direct invocation on deal instance" do
      it "covers the method by direct calls" do
        # Create a simple deal instance
        deal = TestDeal.new
        
        # Test 1: With configured field
        TestDeal.attio_stage_field :test_field
        expect(TestDeal.attio_stage_field).to eq(:test_field)
        expect(TestDeal.attio_stage_field.present?).to be true
        
        # Add the method and test
        deal.define_singleton_method(:test_field) { "value1" }
        expect(deal.respond_to?(:test_field)).to be true
        expect(deal.current_stage_id).to eq("value1")
        
        # Test 2: Without configured field but with stage_id
        TestDeal.attio_stage_field nil
        expect(TestDeal.attio_stage_field).to be_nil
        
        deal.stage_id = "value2"
        expect(deal.respond_to?(:stage_id)).to be true
        expect(deal.current_stage_id).to eq("value2")
        
        # Test 3: Only status available
        deal.stage_id = nil
        deal.status = "value3"
        expect(deal.respond_to?(:status)).to be true
        expect(deal.current_stage_id).to eq("value3")
        
        # Test 4: Nothing available
        deal.status = nil
        expect(deal.current_stage_id).to be_nil
      end
    end

    # Test the actual conditional logic
    context "conditional branch verification" do
      let(:deal) { TestDeal.new }

      it "verifies first condition: attio_stage_field.present? && respond_to?" do
        # Set up both conditions to be true
        TestDeal.attio_stage_field :verified_field
        deal.define_singleton_method(:verified_field) { "verified" }
        
        # Both conditions are true
        expect(TestDeal.attio_stage_field.present?).to be true
        expect(deal.respond_to?(TestDeal.attio_stage_field)).to be true
        
        # Should take first branch
        expect(deal.current_stage_id).to eq("verified")
        
        TestDeal.attio_stage_field nil
      end

      it "verifies elsif respond_to?(:stage_id)" do
        # First condition false, second true
        TestDeal.attio_stage_field nil
        deal.stage_id = "stage_value"
        
        # First condition is false
        expect(TestDeal.attio_stage_field.present?).to be false
        # Second condition is true
        expect(deal.respond_to?(:stage_id)).to be true
        
        # Should take second branch
        expect(deal.current_stage_id).to eq("stage_value")
      end

      it "verifies elsif respond_to?(:status)" do
        # First two conditions false, third true
        TestDeal.attio_stage_field nil
        deal.stage_id = nil
        deal.status = "status_value"
        
        # First condition is false
        expect(TestDeal.attio_stage_field.present?).to be false
        # Second condition is false (no stage_id method)
        if deal.respond_to?(:stage_id)
          deal.instance_eval { undef :stage_id }
        end
        expect(deal.respond_to?(:stage_id)).to be false
        # Third condition is true
        expect(deal.respond_to?(:status)).to be true
        
        # Should take third branch
        expect(deal.current_stage_id).to eq("status_value")
      end
    end
  end
end